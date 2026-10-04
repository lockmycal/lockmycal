defmodule TymeslotWeb.Dashboard.Admin.SettingsActions do
  @moduledoc """
  Settings-tab and email-branding event logic for
  `TymeslotWeb.Dashboard.Admin.HubComponent` — value parsing/validation,
  the actual `AppSettings.update/1` calls, and the logo-upload pipeline.
  Split out of `HubComponent` purely to stay under the project's per-module
  line-count budget; every public function here takes the LiveComponent's
  `socket` and returns `{:noreply, socket}` (or a value `HubComponent`
  folds into one), same contract as if it were still defined there.

  Calls back into `HubComponent.load_settings_data/1` (which reloads
  `effective_values` plus the email-branding preview data every settings
  write must refresh) and `HubComponent.logo_too_large_message/0` (which
  needs the component's own `@logo_max_bytes` module attribute — the single
  place that number lives) rather than duplicating either here.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [upload_errors: 1, upload_errors: 2]
  import Phoenix.LiveView, only: [consume_uploaded_entry: 3, push_event: 3]

  require Logger

  alias Tymeslot.AppSettings
  alias Tymeslot.AppSettings.AppSettingsSchema
  alias Tymeslot.AppSettings.SiteBannerTranslation
  alias Tymeslot.Emails.Branding
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Locales
  alias Tymeslot.Security.SiteBannerScrubber
  alias TymeslotWeb.Dashboard.Admin.Formatters
  alias TymeslotWeb.Dashboard.Admin.HubComponent
  alias TymeslotWeb.Live.Shared.Flash

  @doc "Applies a boolean (Enabled/Disabled tag) or provider (Off/Google/Cloudflare tag) setting change."
  @spec handle_setting_update(
          Phoenix.LiveView.Socket.t(),
          atom(),
          boolean() | :off | :google | :cloudflare,
          String.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_setting_update(socket, atom_key, parsed, state) do
    case AppSettings.update(%{atom_key => parsed}) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> Flash.put_flash(:info, setting_change_message(atom_key, state))
         |> HubComponent.load_settings_data()}

      {:error, :would_lock_out} ->
        {:noreply, Flash.put_flash(socket, :error, lock_out_message(atom_key, parsed))}

      {:error, _changeset} ->
        {:noreply,
         Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Could not update setting."))}
    end
  end

  # Picks the lock-reason copy that matches the specific key/value the admin
  # tried to set. Falls back to a generic message if no tailored clause
  # exists, so an SSO toggle rejection never shows a password-auth message.
  defp lock_out_message(key, value) do
    Formatters.lock_reason(key, value) ||
      dgettext("dashboard_admin", "That change would lock everyone out and was not applied.")
  end

  @doc "Applies a score/email/colour/text/html/size_mb/days setting change."
  @spec handle_typed_setting_update(Phoenix.LiveView.Socket.t(), atom(), term()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_typed_setting_update(socket, key, value) do
    case AppSettings.update(%{key => value}) do
      {:ok, _settings} ->
        {:noreply,
         socket
         |> Flash.put_flash(
           :info,
           dgettext("dashboard_admin", "%{name} updated.", name: Formatters.humanise(key))
         )
         |> push_event("ts:setting-saved", %{key: Atom.to_string(key)})
         |> HubComponent.load_settings_data()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, Flash.put_flash(socket, :error, changeset_message(changeset, key))}

      {:error, _other} ->
        {:noreply,
         Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Could not update setting."))}
    end
  end

  @doc """
  Saves one locale's translation of the site banner message, upserting that
  locale's row and leaving every other row (and the base message) untouched.
  Mirrors the organiser-content translation forms (`BookingTextForm`'s
  `upsert_translation/5`): the rows are rebuilt as params and validated once,
  by `SiteBannerTranslation.changeset/2`, when the setting is written.
  """
  @spec handle_site_banner_translation(Phoenix.LiveView.Socket.t(), String.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_site_banner_translation(socket, locale, raw) do
    translations = AppSettings.get(:site_banner_translations)

    with true <- locale in Locales.supported_codes(),
         {:ok, message} <- parse_html(raw),
         :changed <- translation_change(translations, locale, message) do
      rows = upsert_translation(translations, locale, message)

      handle_typed_setting_update(
        socket,
        :site_banner_translations,
        Enum.map(rows, &translation_row_param/1)
      )
    else
      :unchanged ->
        {:noreply, push_event(socket, "ts:setting-saved", %{key: "site_banner_translations"})}

      _invalid ->
        {:noreply,
         Flash.put_flash(socket, :error, value_invalid_message("site_banner_translations"))}
    end
  end

  defp translation_change(translations, locale, message) do
    case Enum.find(translations, &(&1.locale == locale)) do
      %{message: ^message} -> :unchanged
      nil when is_nil(message) -> :unchanged
      _other -> :changed
    end
  end

  defp upsert_translation(translations, locale, message) do
    case Enum.find_index(translations, &(&1.locale == locale)) do
      nil -> translations ++ [%SiteBannerTranslation{locale: locale, message: message}]
      index -> List.update_at(translations, index, &%{&1 | message: message})
    end
  end

  defp translation_row_param(translation) do
    %{"id" => translation.id, "locale" => translation.locale, "message" => translation.message}
  end

  # Auto-upload progress callback. Consumes the entry only once it is fully
  # uploaded; `consume_uploaded_entry/3` also releases the temporary file, so
  # a rejected PNG leaves nothing behind.
  @doc false
  @spec handle_logo_progress(
          atom(),
          Phoenix.LiveView.UploadEntry.t(),
          Phoenix.LiveView.Socket.t()
        ) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_logo_progress(:email_logo, entry, socket) do
    if entry.done? do
      {:noreply, store_uploaded_logo(socket, entry)}
    else
      {:noreply, socket}
    end
  end

  defp store_uploaded_logo(socket, entry) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Branding.store_logo(path)}
      end)

    case result do
      {:ok, _relative} ->
        socket
        |> Flash.put_flash(:info, dgettext("dashboard_admin", "Email logo updated."))
        |> HubComponent.load_settings_data()

      {:error, :not_a_png} ->
        Flash.put_flash(
          socket,
          :error,
          dgettext("dashboard_admin", "That file is not a valid image and was not saved.")
        )

      {:error, reason} ->
        Logger.warning("Failed to store email logo", reason: LogFormat.reason(reason))
        Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Could not save the logo."))
    end
  end

  # Config-level errors (`:too_many_files`) come from `upload_errors/1`; a
  # rejected entry (`:too_large`, `:not_accepted`, or a disk-level
  # `{:writer_failure, reason}`) only shows up per-entry via `upload_errors/2`
  # - without iterating entries those never reach the admin at all.
  @spec logo_error_messages(Phoenix.LiveView.UploadConfig.t()) :: [String.t()]
  def logo_error_messages(upload) do
    config_errors = upload |> upload_errors() |> Enum.map(&upload_error_message/1)

    entry_errors =
      upload.entries
      |> Enum.flat_map(&upload_errors(upload, &1))
      |> Enum.map(&upload_error_message/1)

    config_errors ++ entry_errors
  end

  defp upload_error_message(:too_large), do: HubComponent.logo_too_large_message()

  defp upload_error_message(:not_accepted),
    do: dgettext("dashboard_admin", "That file type is not supported.")

  defp upload_error_message(:too_many_files),
    do: dgettext("dashboard_admin", "Upload one logo at a time.")

  defp upload_error_message(_other),
    do: dgettext("dashboard_admin", "The logo could not be uploaded.")

  @spec parse_setting_key(String.t()) :: {:ok, atom()} | :error
  def parse_setting_key(key) do
    AppSettings.keys()
    |> Map.new(fn k -> {Atom.to_string(k), k} end)
    |> Map.fetch(key)
  end

  @spec parse_setting_value(String.t()) ::
          {:ok, boolean() | :off | :google | :cloudflare} | :error
  def parse_setting_value("true"), do: {:ok, true}
  def parse_setting_value("false"), do: {:ok, false}
  def parse_setting_value("off"), do: {:ok, :off}
  def parse_setting_value("google"), do: {:ok, :google}
  def parse_setting_value("cloudflare"), do: {:ok, :cloudflare}
  def parse_setting_value(_other), do: :error

  defp setting_change_message(key, "true"),
    do: dgettext("dashboard_admin", "%{name} enabled.", name: Formatters.humanise(key))

  defp setting_change_message(key, "false"),
    do: dgettext("dashboard_admin", "%{name} disabled.", name: Formatters.humanise(key))

  defp setting_change_message(key, state) when state in ["off", "google", "cloudflare"],
    do:
      dgettext("dashboard_admin", "%{name} set to %{value}.",
        name: Formatters.humanise(key),
        value: provider_label(state)
      )

  defp provider_label("off"), do: dgettext("dashboard_admin", "Off")
  defp provider_label("google"), do: "Google"
  defp provider_label("cloudflare"), do: "Cloudflare"

  @spec parse_typed_value(atom(), String.t()) :: {:ok, term()} | :invalid
  def parse_typed_value(key, raw) do
    case Formatters.kind(key) do
      :score ->
        parse_score(raw)

      :email ->
        parse_email(raw)

      :colour ->
        parse_colour(raw)

      :text ->
        parse_text(raw)

      :html ->
        parse_html(raw)

      :locale ->
        parse_locale(raw)

      :size_mb ->
        parse_size_mb(raw)

      :days ->
        parse_days(raw)

      :attachment_size_mb ->
        parse_bounded_integer(raw, 100)

      :file_count ->
        parse_bounded_integer(raw, 10)

      kind when kind in [:boolean, :logo, :translations, :audit_events, :attachment_types] ->
        :invalid
    end
  end

  @spec detect_change(Phoenix.LiveView.Socket.t(), atom(), term()) :: :changed | :unchanged
  def detect_change(socket, key, value) do
    case get_in(socket.assigns, [:effective_values, key]) do
      %{value: ^value} -> :unchanged
      _other -> :changed
    end
  end

  # Empty string clears the override. Trim to avoid whitespace-only inputs
  # reaching the schema.
  defp parse_email(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp parse_email(_other), do: :invalid

  defp parse_score(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {score, ""} when score >= 0.0 and score <= 1.0 -> {:ok, score}
      _other -> :invalid
    end
  end

  defp parse_score(_other), do: :invalid

  # Normalised here as well as in the changeset so `detect_change/3` compares
  # like with like: the native colour picker submits "#14B8A6" where the row
  # holds "#14b8a6", and an unnormalised comparison would read as a change and
  # flash "updated" on every tab-through.
  defp parse_colour(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed -> normalised_colour(trimmed)
    end
  end

  defp parse_colour(_other), do: :invalid

  defp normalised_colour(value) do
    case Branding.normalise_accent(value) do
      nil -> :invalid
      hex -> {:ok, hex}
    end
  end

  # The supported set is configuration, so an unrecognised code is rejected
  # here as well as in the changeset: the buttons can only offer valid codes,
  # which makes anything else a hand-crafted submission.
  defp parse_locale(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      code -> if code in Locales.supported_codes(), do: {:ok, code}, else: :invalid
    end
  end

  defp parse_locale(_other), do: :invalid

  defp parse_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, nil}
      trimmed -> {:ok, trimmed}
    end
  end

  defp parse_text(_other), do: :invalid

  # Sanitised with the same allow-list the changeset applies, so
  # `detect_change/3` compares against what would actually be stored: a
  # message whose only difference is stripped markup is a no-op, not an
  # "updated" flash on every blur.
  defp parse_html(value) when is_binary(value) do
    case value |> SiteBannerScrubber.sanitize() |> String.trim() do
      "" -> {:ok, nil}
      html -> {:ok, html}
    end
  end

  defp parse_html(_other), do: :invalid

  defp parse_size_mb(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {mb, ""} when mb > 0 and mb <= 2000 -> {:ok, mb}
      _other -> :invalid
    end
  end

  defp parse_size_mb(_other), do: :invalid

  defp parse_days(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {days, ""} when days > 0 and days <= 3650 -> {:ok, days}
      _other -> :invalid
    end
  end

  defp parse_days(_other), do: :invalid

  defp parse_bounded_integer(value, max) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 and number <= max -> {:ok, number}
      _other -> :invalid
    end
  end

  defp parse_bounded_integer(_other, _max), do: :invalid

  @doc """
  Adds `type` to, or removes it from, the file types a booker may attach,
  keeping the supported types' display order. Removing the last one switches
  booking attachments off for the install.
  """
  @spec toggle_booking_attachment_type(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def toggle_booking_attachment_type(socket, type) do
    supported = AppSettingsSchema.booking_attachment_types()

    if type in supported do
      current = AppSettings.get(:booking_attachment_types)

      selected =
        Enum.filter(supported, fn candidate ->
          if candidate == type, do: candidate not in current, else: candidate in current
        end)

      handle_typed_setting_update(socket, :booking_attachment_types, selected)
    else
      {:noreply,
       Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Could not update setting."))}
    end
  end

  @spec value_invalid_message(String.t()) :: String.t()
  def value_invalid_message(key) do
    case parse_setting_key(key) do
      {:ok, atom_key} ->
        case Formatters.kind(atom_key) do
          :score ->
            dgettext("dashboard_admin", "Enter a number between 0.0 and 1.0.")

          :email ->
            dgettext("dashboard_admin", "Enter a valid email address.")

          :colour ->
            dgettext("dashboard_admin", "Enter a hex colour such as #14b8a6.")

          :text ->
            dgettext("dashboard_admin", "That value is too long.")

          kind when kind in [:html, :translations] ->
            dgettext("dashboard_admin", "Keep the message under 1000 characters.")

          :locale ->
            dgettext("dashboard_admin", "Choose one of the supported languages.")

          :size_mb ->
            dgettext("dashboard_admin", "Enter a whole number of megabytes (1-2000).")

          :days ->
            dgettext("dashboard_admin", "Enter a whole number of days (1-3650).")

          :attachment_size_mb ->
            dgettext("dashboard_admin", "Enter a whole number of megabytes (1-100).")

          :file_count ->
            dgettext("dashboard_admin", "Enter a whole number of files (1-10).")

          _other ->
            dgettext("dashboard_admin", "Could not update setting.")
        end

      _other ->
        dgettext("dashboard_admin", "Could not update setting.")
    end
  end

  # Changeset errors from validate_format ("has invalid format") and
  # validate_number ("must be greater than or equal to 0.0", etc.) are
  # accurate but not friendly. Map them to the same human messages the inline
  # parser uses so admins see one consistent phrasing whichever guard catches
  # the bad input.
  defp changeset_message(%Ecto.Changeset{errors: errors}, key) do
    case Keyword.get(errors, key) do
      {_message, _meta} -> value_invalid_message(Atom.to_string(key))
      nil -> dgettext("dashboard_admin", "Could not update setting.")
    end
  end
end
