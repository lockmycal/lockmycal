defmodule Tymeslot.AppSettings.AppSettingsSchema do
  @moduledoc """
  Schema for the singleton `app_settings` row that stores admin-editable
  runtime overrides for values that would otherwise come from config.exs /
  environment variables.

  Each field is nullable — `nil` means "no DB override, fall back to the
  application config default". The table is constrained to a single row via
  a `CHECK (id = 1)` constraint defined in the migration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Tymeslot.AppSettings.SiteBannerTranslation
  alias Tymeslot.ChangesetValidators.Translations
  alias Tymeslot.Locales
  alias Tymeslot.Security.AuditLog.Catalog
  alias Tymeslot.Security.SiteBannerScrubber
  alias Tymeslot.Utils.Colour

  @type t :: %__MODULE__{
          id: integer() | nil,
          registration_enabled: boolean() | nil,
          password_auth_enabled: boolean() | nil,
          google_auth_enabled: boolean() | nil,
          github_auth_enabled: boolean() | nil,
          microsoft_auth_enabled: boolean() | nil,
          oauth_auth_enabled: boolean() | nil,
          recaptcha_signup_provider: :off | :google | :cloudflare | nil,
          recaptcha_booking_provider: :off | :google | :cloudflare | nil,
          recaptcha_signup_min_score: float() | nil,
          recaptcha_booking_min_score: float() | nil,
          admin_alerts_enabled: boolean() | nil,
          admin_alert_email: String.t() | nil,
          meeting_payments_enabled: boolean() | nil,
          booking_analytics_enabled: boolean() | nil,
          email_brand_accent: String.t() | nil,
          email_brand_name: String.t() | nil,
          email_logo_path: String.t() | nil,
          admin_default_locale: String.t() | nil,
          booking_default_locale: String.t() | nil,
          max_image_upload_size_mb: integer() | nil,
          max_video_upload_size_mb: integer() | nil,
          audit_log_retention_days: integer() | nil,
          audit_log_events: map() | nil,
          site_banner_app_enabled: boolean() | nil,
          site_banner_auth_enabled: boolean() | nil,
          site_banner_public_enabled: boolean() | nil,
          site_banner_message: String.t() | nil,
          site_banner_colour: String.t() | nil,
          site_banner_translations: [SiteBannerTranslation.t()],
          admin_bootstrapped_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @editable_fields [
    :registration_enabled,
    :password_auth_enabled,
    :google_auth_enabled,
    :github_auth_enabled,
    :microsoft_auth_enabled,
    :oauth_auth_enabled,
    :recaptcha_signup_provider,
    :recaptcha_booking_provider,
    :recaptcha_signup_min_score,
    :recaptcha_booking_min_score,
    :admin_alerts_enabled,
    :admin_alert_email,
    :meeting_payments_enabled,
    :booking_analytics_enabled,
    :email_brand_accent,
    :email_brand_name,
    :email_logo_path,
    :admin_default_locale,
    :booking_default_locale,
    :max_image_upload_size_mb,
    :max_video_upload_size_mb,
    :audit_log_retention_days,
    :audit_log_events,
    :site_banner_app_enabled,
    :site_banner_auth_enabled,
    :site_banner_public_enabled,
    :site_banner_message,
    :site_banner_colour,
    :site_banner_translations
  ]

  # Editable settings stored as an `embeds_many`: cast with `cast_embed/3`
  # rather than `cast/3`, and "no override" is `[]` rather than `nil`.
  @embed_fields [:site_banner_translations]

  @locale_fields [:admin_default_locale, :booking_default_locale]

  @score_fields [:recaptcha_signup_min_score, :recaptcha_booking_min_score]
  @upload_size_fields [:max_image_upload_size_mb, :max_video_upload_size_mb]

  # Ten years: bounded so a typo can't store a value the prune arithmetic
  # overflows on, while leaving any real retention policy possible.
  @max_audit_log_retention_days 3650

  # Free-text overrides where an empty input means "clear the override"
  # rather than "store an empty string", so the UI can submit a blanked
  # field without special-casing it.
  @blankable_fields [
    :admin_alert_email,
    :email_brand_accent,
    :email_brand_name,
    :email_logo_path,
    :admin_default_locale,
    :booking_default_locale,
    :site_banner_message,
    :site_banner_colour
  ]

  # Pragmatic email pattern — same shape as the user-facing validation in
  # Tymeslot.Auth. Catches obvious typos; the upstream mail adapter does the
  # rest.
  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  # A brand name lands in the inbox preview line and the organiser strip, both
  # of which are truncated by mail clients well before this; the cap only stops
  # an accidental paste of something enormous.
  @max_brand_name_length 60

  # The column is a bare `:string`, i.e. `varchar(255)` — a byte limit, not a
  # grapheme limit. `validate_length/3` counts graphemes by default, so a
  # 60-grapheme multi-byte name (emoji, Devanagari, Thai, ...) can pass the
  # display cap above yet still overflow storage. Validate bytes too so that
  # case is rejected with a changeset error instead of a Postgres crash.
  @max_brand_name_bytes 255

  # The banner is a single bar across the top of every page; the cap stops an
  # accidental paste of a whole document, not a sensible announcement.
  @max_site_banner_message_length 1000

  schema "app_settings" do
    field(:registration_enabled, :boolean)
    field(:password_auth_enabled, :boolean)
    field(:google_auth_enabled, :boolean)
    field(:github_auth_enabled, :boolean)
    field(:microsoft_auth_enabled, :boolean)
    field(:oauth_auth_enabled, :boolean)
    field(:recaptcha_signup_provider, Ecto.Enum, values: [:off, :google, :cloudflare])
    field(:recaptcha_booking_provider, Ecto.Enum, values: [:off, :google, :cloudflare])
    field(:recaptcha_signup_min_score, :float)
    field(:recaptcha_booking_min_score, :float)
    field(:admin_alerts_enabled, :boolean)
    field(:admin_alert_email, :string)
    field(:meeting_payments_enabled, :boolean)
    field(:booking_analytics_enabled, :boolean)
    field(:email_brand_accent, :string)
    field(:email_brand_name, :string)
    field(:email_logo_path, :string)
    field(:admin_default_locale, :string)
    field(:booking_default_locale, :string)
    field(:max_image_upload_size_mb, :integer)
    field(:max_video_upload_size_mb, :integer)
    field(:audit_log_retention_days, :integer)
    # Per-category overrides, `%{category_key => boolean}`; a category
    # without one uses its default (`Tymeslot.Security.AuditLog.Catalog`).
    field(:audit_log_events, :map)
    field(:site_banner_app_enabled, :boolean)
    field(:site_banner_auth_enabled, :boolean)
    field(:site_banner_public_enabled, :boolean)
    field(:site_banner_message, :string)
    field(:site_banner_colour, :string)

    embeds_many(:site_banner_translations, SiteBannerTranslation, on_replace: :delete)

    # Not admin-editable: set once, by `Tymeslot.Auth.AdminBootstrap`, when the
    # first-user-becomes-admin bootstrap closes. Never cast from params.
    field(:admin_bootstrapped_at, :utc_datetime)

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the list of admin-editable setting keys.
  """
  @spec editable_fields() :: [atom()]
  def editable_fields, do: @editable_fields

  @doc """
  Changeset for updating one or more admin-editable settings.
  Each cast value may be `nil` to clear the override and fall back to the
  application config default.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(settings, attrs) do
    settings
    |> cast(normalise(attrs), @editable_fields -- @embed_fields)
    |> cast_embed(:site_banner_translations, with: &SiteBannerTranslation.changeset/2)
    |> Translations.validate_unique_locales(:site_banner_translations)
    |> validate_scores()
    |> validate_admin_alert_email()
    |> validate_brand_accent()
    |> validate_brand_name()
    |> validate_logo_path()
    |> validate_locales()
    |> validate_upload_sizes()
    |> validate_number(:audit_log_retention_days,
      greater_than: 0,
      less_than_or_equal_to: @max_audit_log_retention_days
    )
    |> validate_audit_log_events()
    |> validate_site_banner_message()
    |> validate_site_banner_colour()
  end

  defp normalise(attrs) do
    attrs
    |> clear_embeds()
    |> blank_free_text()
  end

  # Clearing an override (`AppSettings.reset/1`, or `update/1` with `nil`)
  # means "no translations" for an embed, which `cast_embed/3` only accepts
  # as an empty list.
  defp clear_embeds(attrs) do
    Enum.reduce(@embed_fields, attrs, fn field, acc ->
      case Map.fetch(acc, field) do
        {:ok, nil} -> Map.put(acc, field, [])
        _absent_or_set -> acc
      end
    end)
  end

  # Trim every free-text override, treating a blank result as "clear the
  # override" so the UI does not have to special-case an emptied input.
  defp blank_free_text(attrs) do
    Enum.reduce(@blankable_fields, attrs, fn field, acc ->
      case Map.fetch(acc, field) do
        {:ok, value} when is_binary(value) ->
          Map.put(acc, field, blank_to_nil(value))

        _absent_or_already_nil ->
          acc
      end
    end)
  end

  defp blank_to_nil(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_scores(changeset) do
    Enum.reduce(@score_fields, changeset, fn field, acc ->
      validate_number(acc, field,
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0
      )
    end)
  end

  # Whole megabytes only, and bounded well above the largest sane background
  # asset (2000MB) so a typo can't wedge an unusable value into the DB.
  defp validate_upload_sizes(changeset) do
    Enum.reduce(@upload_size_fields, changeset, fn field, acc ->
      validate_number(acc, field, greater_than: 0, less_than_or_equal_to: 2000)
    end)
  end

  defp validate_audit_log_events(changeset) do
    validate_change(changeset, :audit_log_events, fn :audit_log_events, overrides ->
      valid? =
        Enum.all?(overrides, fn {key, value} ->
          key in Catalog.keys() and is_boolean(value)
        end)

      if valid?,
        do: [],
        else: [audit_log_events: "has an unknown category or a non-boolean value"]
    end)
  end

  defp validate_admin_alert_email(changeset) do
    case fetch_change(changeset, :admin_alert_email) do
      {:ok, nil} -> changeset
      {:ok, _email} -> validate_format(changeset, :admin_alert_email, @email_regex)
      :error -> changeset
    end
  end

  # Sanitised on write so the row only ever holds allow-listed HTML;
  # `Tymeslot.SiteBanner` sanitises again on render as defence in depth. A
  # message that is nothing but stripped markup is stored as a cleared
  # override rather than an empty string.
  defp validate_site_banner_message(changeset) do
    case fetch_change(changeset, :site_banner_message) do
      {:ok, value} when is_binary(value) ->
        changeset
        |> put_change(:site_banner_message, sanitise_banner_message(value))
        |> validate_length(:site_banner_message, max: @max_site_banner_message_length)

      _nil_or_unchanged ->
        changeset
    end
  end

  defp sanitise_banner_message(value) do
    value
    |> SiteBannerScrubber.sanitize()
    |> blank_to_nil()
  end

  defp validate_site_banner_colour(changeset) do
    case fetch_change(changeset, :site_banner_colour) do
      {:ok, value} when is_binary(value) ->
        case Colour.normalise_hex(value) do
          nil -> add_error(changeset, :site_banner_colour, "must be a hex colour such as #14b8a6")
          hex -> put_change(changeset, :site_banner_colour, hex)
        end

      _nil_or_unchanged ->
        changeset
    end
  end

  # Stored normalised to lowercase `#rrggbb` so everything downstream — the
  # derivation cache key, the colour input, the preview swatch — compares and
  # renders one form rather than three.
  defp validate_brand_accent(changeset) do
    case fetch_change(changeset, :email_brand_accent) do
      {:ok, nil} ->
        changeset

      {:ok, value} ->
        case Colour.normalise_hex(value) do
          nil ->
            add_error(changeset, :email_brand_accent, "must be a hex colour such as #14b8a6")

          hex ->
            put_change(changeset, :email_brand_accent, hex)
        end

      :error ->
        changeset
    end
  end

  defp validate_brand_name(changeset) do
    changeset
    |> validate_length(:email_brand_name, max: @max_brand_name_length)
    |> validate_length(:email_brand_name, max: @max_brand_name_bytes, count: :bytes)
  end

  # The stored path is relative to the configured upload directory and is
  # written only by `Tymeslot.Emails.Branding`. Rejecting absolute paths and
  # traversal here is defence in depth: it means no value that could escape
  # the upload directory can reach the row at all, whatever writes it.
  defp validate_logo_path(changeset) do
    case fetch_change(changeset, :email_logo_path) do
      {:ok, nil} ->
        changeset

      {:ok, path} ->
        if Path.type(path) == :relative and not traversal?(path) do
          changeset
        else
          add_error(changeset, :email_logo_path, "must be a relative path inside the upload dir")
        end

      :error ->
        changeset
    end
  end

  # The supported set is configuration, so it is read at validation time
  # rather than baked into the module: an install that has removed a language
  # must not be able to select it. Nil is the cleared override and passes
  # untouched: `validate_inclusion/3` only sees a change that is present.
  defp validate_locales(changeset) do
    Enum.reduce(@locale_fields, changeset, fn field, acc ->
      validate_inclusion(acc, field, Locales.supported_codes(),
        message: "is not a supported language"
      )
    end)
  end

  defp traversal?(path), do: ".." in Path.split(path)
end
