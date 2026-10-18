defmodule TymeslotWeb.Dashboard.ThemeSettings.BrandLogoComponent do
  @moduledoc """
  Dashboard section for the organizer's own logo (`Tymeslot.Profiles.BrandLogo`),
  shown instead of the app logo on their public pages and in the emails about
  their meetings. Applies to every theme.

  The upload works like the admin's email logo
  (`TymeslotWeb.Dashboard.Admin.EmailBrandingRows.email_logo_row/1`): the
  `EmailLogoUpload` hook rasterises whatever was picked (PNG, JPEG, WebP, SVG)
  to a PNG in the browser, because mail clients render nothing else reliably,
  and `BrandLogo.store/2` re-validates it on the server.

  Gated by the `custom_branding_allowed` assign (defaults to `true`, same
  self-host-open convention as the rest of `:feature_assigns` — see
  `TymeslotWeb.Hooks.FeatureAssignsHook`): when `false`, the upload is
  replaced by the upgrade placeholder registered under
  `:feature_placeholder_components[:custom_branding]` (rendered with
  `feature` and `current_user`, as the group-bookings section does), or by a
  plain locked notice when none is registered. A logo stored earlier can
  still be removed.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Profiles.BrandLogo
  alias Tymeslot.Security.RateLimiter
  alias TymeslotWeb.Components.Dashboard.ProBadge
  alias TymeslotWeb.Components.Dashboard.ProNotice
  alias TymeslotWeb.Live.Shared.Flash

  require Logger

  # A 512px-wide PNG lands far under this; the cap is a backstop against a
  # client that skips the hook. It also feeds the hook's client-side guard.
  @max_bytes 2_000_000
  # 2x the widest the logo is shown (the public top bar), so it stays sharp on
  # high-density screens.
  @render_width 512

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(max_bytes: @max_bytes, render_width: @render_width)
     |> allow_upload(:brand_logo,
       accept: ~w(.png),
       max_entries: 1,
       max_file_size: @max_bytes,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    {:ok,
     socket
     |> assign_new(:custom_branding_allowed, fn -> true end)
     |> assign(:logo_url, BrandLogo.url(socket.assigns.profile))}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    placeholder = if assigns.custom_branding_allowed, do: nil, else: placeholder_component()

    assigns =
      assigns
      |> assign(:errors, error_messages(assigns.uploads.brand_logo))
      |> assign(:placeholder_component, placeholder)

    ~H"""
    <div id={@id} class="mt-16">
      <%!-- Title passed as the slot, not `title`, so the Pro badge sits right
            after it instead of at the far end of the row. --%>
      <.section_header level={2} icon="hero-photo">
        <span class="inline-flex items-center gap-3">
          {dgettext("dashboard_appearance", "Your Logo")}
          <ProBadge.pro_badge :if={!@custom_branding_allowed} />
        </span>
      </.section_header>

      <div :if={is_nil(@placeholder_component)} class="mb-10 max-w-2xl">
        <p class="text-xl text-neutral-500 font-medium leading-relaxed dark:text-twilight-indigo-300">
          {dgettext(
            "dashboard_appearance",
            "Show your own logo instead of ours at the top of your booking page and in the emails about your meetings. Applies to every theme."
          )}
        </p>
      </div>

      <div :if={@placeholder_component} class="mt-6">
        <.live_component
          module={@placeholder_component}
          id={"#{@id}-upgrade"}
          feature={:custom_branding}
          current_user={assigns[:current_user]}
        />
      </div>

      <%!-- While locked behind a placeholder, the card only remains to remove a
            logo stored earlier. --%>
      <.card
        :if={is_nil(@placeholder_component) or @logo_url}
        padding={:lg}
        class={["max-w-2xl", @placeholder_component && "mt-6"]}
      >
        <div class="flex items-center justify-between gap-6 flex-wrap">
          <div class="flex items-center gap-4 min-w-0">
            <%= if @logo_url do %>
              <div class="px-4 py-3 rounded-token-xl bg-neutral-800 border-2 border-neutral-300">
                <img
                  src={@logo_url}
                  alt={dgettext("dashboard_appearance", "Current logo")}
                  class="h-12 w-auto max-w-64 object-contain"
                />
              </div>
            <% else %>
              <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-300">
                {dgettext("dashboard_appearance", "No logo uploaded. The default logo is shown.")}
              </p>
            <% end %>
          </div>

          <div class="flex items-center gap-3 shrink-0">
            <.action_button
              :if={@logo_url}
              variant={:secondary}
              icon="hero-trash"
              phx-click="remove_brand_logo"
              phx-target={@myself}
            >
              {dgettext("dashboard_appearance", "Remove")}
            </.action_button>

            <form
              :if={@custom_branding_allowed}
              id={"#{@id}-form"}
              phx-change="validate_brand_logo"
              phx-target={@myself}
            >
              <%!-- The hook hands the converted PNG to this hidden uploader via
                    `this.upload/2`, which looks the input up by name. --%>
              <.live_file_input upload={@uploads.brand_logo} class="hidden" />

              <label class="btn btn-primary cursor-pointer focus-within:outline-hidden focus-within:ring-2 focus-within:ring-primary-500 focus-within:ring-offset-2">
                <.icon name="hero-arrow-up-tray-mini" class="w-4 h-4" />
                {if @logo_url,
                  do: dgettext("dashboard_appearance", "Replace"),
                  else: dgettext("dashboard_appearance", "Upload logo")}
                <input
                  id={"#{@id}-picker"}
                  type="file"
                  accept="image/png,image/jpeg,image/webp,image/svg+xml"
                  class="sr-only"
                  phx-hook="EmailLogoUpload"
                  phx-target={@myself}
                  phx-update="ignore"
                  aria-describedby={"#{@id}-errors"}
                  data-upload-name="brand_logo"
                  data-render-width={@render_width}
                  data-max-bytes={@max_bytes}
                />
              </label>
            </form>
          </div>
        </div>

        <ProNotice.pro_notice
          :if={!@custom_branding_allowed and is_nil(@placeholder_component)}
          class="mt-6"
        >
          {dgettext(
            "dashboard_appearance",
            "Your own logo is available on the Pro plan and higher. Until then the default logo is shown."
          )}
        </ProNotice.pro_notice>

        <div id={"#{@id}-errors"} aria-live="polite">
          <p :for={message <- @errors} class="mt-4 text-token-sm font-bold text-red-600">
            {message}
          </p>
        </div>
      </.card>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate_brand_logo", _params, socket), do: {:noreply, socket}

  # Pushed by the `EmailLogoUpload` hook when the browser cannot decode the
  # picked file, or before uploading a file over `@max_bytes`.
  def handle_event("email_logo_conversion_failed", _params, socket) do
    {:noreply,
     Flash.put_flash(
       socket,
       :error,
       dgettext("dashboard_appearance", "That image could not be read. Try a PNG or JPEG file.")
     )}
  end

  def handle_event("email_logo_too_large", _params, socket) do
    {:noreply, Flash.put_flash(socket, :error, too_large_message())}
  end

  def handle_event("remove_brand_logo", _params, socket) do
    profile = socket.assigns.profile

    with :ok <- check_rate_limit(profile.user_id),
         {:ok, updated} <- BrandLogo.remove(profile) do
      send(self(), {:profile_updated, updated})

      {:noreply,
       socket
       |> assign(profile: updated, logo_url: nil)
       |> Flash.put_flash(:info, dgettext("dashboard_appearance", "Logo removed."))}
    else
      {:error, :rate_limited} ->
        {:noreply, Flash.put_flash(socket, :error, rate_limited_message())}

      {:error, reason} ->
        Logger.warning("Failed to remove organizer logo", reason: LogFormat.reason(reason))

        {:noreply,
         Flash.put_flash(
           socket,
           :error,
           dgettext("dashboard_appearance", "Could not remove the logo.")
         )}
    end
  end

  # Consumes the entry only once it is fully uploaded; `consume_uploaded_entry/3`
  # also releases the temporary file, so a rejected upload leaves nothing behind.
  defp handle_progress(:brand_logo, entry, socket) do
    if entry.done? do
      {:noreply, store_uploaded_logo(socket, entry)}
    else
      {:noreply, socket}
    end
  end

  defp store_uploaded_logo(socket, entry) do
    profile = socket.assigns.profile

    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        case check_rate_limit(profile.user_id) do
          :ok -> {:ok, BrandLogo.store(profile, path)}
          error -> {:ok, error}
        end
      end)

    case result do
      {:ok, updated} ->
        send(self(), {:profile_updated, updated})

        socket
        |> assign(profile: updated, logo_url: BrandLogo.url(updated))
        |> Flash.put_flash(:info, dgettext("dashboard_appearance", "Logo updated."))

      {:error, :rate_limited} ->
        Flash.put_flash(socket, :error, rate_limited_message())

      {:error, :not_allowed} ->
        Flash.put_flash(
          socket,
          :error,
          dgettext(
            "dashboard_appearance",
            "Your own logo is available on the Pro plan and higher."
          )
        )

      {:error, :not_a_png} ->
        Flash.put_flash(
          socket,
          :error,
          dgettext("dashboard_appearance", "That file is not a valid image and was not saved.")
        )

      {:error, reason} ->
        Logger.warning("Failed to store organizer logo", reason: LogFormat.reason(reason))

        Flash.put_flash(
          socket,
          :error,
          dgettext("dashboard_appearance", "Could not save the logo.")
        )
    end
  end

  # Bracket access works for both a keyword list and a map. Core leaves the
  # config unset; the managed overlay registers one.
  defp placeholder_component do
    case Application.get_env(:tymeslot, :feature_placeholder_components) do
      nil -> nil
      placeholders -> placeholders[:custom_branding]
    end
  end

  defp check_rate_limit(user_id) do
    case RateLimiter.check_brand_logo_upload_rate_limit(user_id) do
      :ok -> :ok
      {:error, :rate_limited, _message} -> {:error, :rate_limited}
      {:error, reason} -> {:error, reason}
    end
  end

  # Config-level errors come from `upload_errors/1`; a rejected entry only
  # shows up per entry via `upload_errors/2`.
  defp error_messages(upload) do
    config_errors = upload |> upload_errors() |> Enum.map(&upload_error_message/1)

    entry_errors =
      upload.entries
      |> Enum.flat_map(&upload_errors(upload, &1))
      |> Enum.map(&upload_error_message/1)

    Enum.uniq(config_errors ++ entry_errors)
  end

  defp upload_error_message(:too_large), do: too_large_message()

  defp upload_error_message(:not_accepted),
    do: dgettext("dashboard_appearance", "That file type is not supported.")

  defp upload_error_message(:too_many_files),
    do: dgettext("dashboard_appearance", "Upload one logo at a time.")

  defp upload_error_message(_other),
    do: dgettext("dashboard_appearance", "The logo could not be uploaded.")

  defp too_large_message,
    do: dgettext("dashboard_appearance", "The logo is too large. The maximum size is 2 MB.")

  defp rate_limited_message,
    do:
      dgettext(
        "dashboard_appearance",
        "Too many logo changes. Please wait a while and try again."
      )
end
