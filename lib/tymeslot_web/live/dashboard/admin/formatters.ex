defmodule TymeslotWeb.Dashboard.Admin.Formatters do
  @moduledoc """
  Pure formatting helpers shared across the admin tabs.

  Centralised here so labels and value rendering stay consistent between the
  overview, settings, and users tabs.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Locales

  @doc "Human-readable label for an `AppSettings` key."
  @spec humanise(atom()) :: String.t()
  def humanise(:registration_enabled), do: dgettext("dashboard_admin", "Registration enabled")
  def humanise(:password_auth_enabled), do: dgettext("dashboard_admin", "Password authentication")
  def humanise(:google_auth_enabled), do: dgettext("dashboard_admin", "Google login")
  def humanise(:github_auth_enabled), do: dgettext("dashboard_admin", "GitHub login")
  def humanise(:microsoft_auth_enabled), do: dgettext("dashboard_admin", "Microsoft login")
  def humanise(:oauth_auth_enabled), do: dgettext("dashboard_admin", "Generic OIDC login")

  def humanise(:recaptcha_signup_provider),
    do: dgettext("dashboard_admin", "Bot protection on signup")

  def humanise(:recaptcha_booking_provider),
    do: dgettext("dashboard_admin", "Bot protection on booking")

  def humanise(:recaptcha_signup_min_score), do: dgettext("dashboard_admin", "Signup min score")
  def humanise(:recaptcha_booking_min_score), do: dgettext("dashboard_admin", "Booking min score")
  def humanise(:admin_alerts_enabled), do: dgettext("dashboard_admin", "Admin alerts")
  def humanise(:admin_alert_email), do: dgettext("dashboard_admin", "Admin alert recipient")
  def humanise(:meeting_payments_enabled), do: dgettext("dashboard_admin", "Meeting payments")
  def humanise(:booking_analytics_enabled), do: dgettext("dashboard_admin", "Booking analytics")
  def humanise(:email_brand_accent), do: dgettext("dashboard_admin", "Email accent colour")
  def humanise(:email_brand_name), do: dgettext("dashboard_admin", "Email brand name")
  def humanise(:email_logo_path), do: dgettext("dashboard_admin", "Email logo")

  def humanise(:admin_default_locale),
    do: dgettext("dashboard_admin", "Dashboard fallback language")

  def humanise(:booking_default_locale),
    do: dgettext("dashboard_admin", "Booking page fallback language")

  def humanise(:max_image_upload_size_mb),
    do: dgettext("dashboard_admin", "Max background image size")

  def humanise(:max_video_upload_size_mb),
    do: dgettext("dashboard_admin", "Max background video size")

  def humanise(:booking_attachment_types), do: dgettext("dashboard_admin", "Allowed file types")

  def humanise(:max_booking_attachment_size_mb),
    do: dgettext("dashboard_admin", "Max size per file")

  def humanise(:max_booking_attachments),
    do: dgettext("dashboard_admin", "Max files per booking")

  def humanise(:audit_log_retention_days),
    do: dgettext("dashboard_admin", "Keep audit events for")

  def humanise(:audit_log_events), do: dgettext("dashboard_admin", "Logged events")

  def humanise(:site_banner_app_enabled), do: dgettext("dashboard_admin", "Show in the app")

  def humanise(:site_banner_auth_enabled),
    do: dgettext("dashboard_admin", "Show on sign-in pages")

  def humanise(:site_banner_public_enabled),
    do: dgettext("dashboard_admin", "Show on public booking pages")

  def humanise(:site_banner_message), do: dgettext("dashboard_admin", "Banner message")
  def humanise(:site_banner_colour), do: dgettext("dashboard_admin", "Banner colour")

  def humanise(:site_banner_translations),
    do: dgettext("dashboard_admin", "Banner message translations")

  def humanise(key),
    do: key |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()

  @doc """
  Short, human-readable description of what a setting controls. Shown
  beneath the setting name on the admin settings page.

  The recommended value is rendered separately by `recommended/1` so the
  UI can give it its own visual treatment.
  """
  @spec describe(atom()) :: String.t()
  def describe(:registration_enabled) do
    dgettext(
      "dashboard_admin",
      "Allow new users to sign up via the public registration page. Disable for a private install where admins create accounts manually."
    )
  end

  def describe(:password_auth_enabled) do
    dgettext(
      "dashboard_admin",
      "Allow log-in with email and password. When disabled, users can only authenticate through configured OAuth providers."
    )
  end

  def describe(:google_auth_enabled) do
    dgettext(
      "dashboard_admin",
      "Show the \"Continue with Google\" button on login and signup. Requires GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET to be set in the environment."
    )
  end

  def describe(:github_auth_enabled) do
    dgettext(
      "dashboard_admin",
      "Show the \"Continue with GitHub\" button on login and signup. Requires GITHUB_CLIENT_ID and GITHUB_CLIENT_SECRET to be set in the environment."
    )
  end

  def describe(:microsoft_auth_enabled) do
    dgettext(
      "dashboard_admin",
      "Show the \"Continue with Microsoft\" button on login and signup, for personal and work or school accounts. Uses the Outlook/Teams app registration (OUTLOOK_CLIENT_ID and OUTLOOK_CLIENT_SECRET); add /auth/microsoft/callback to its redirect URIs."
    )
  end

  def describe(:oauth_auth_enabled) do
    dgettext(
      "dashboard_admin",
      "Enable generic OAuth 2.0 / OIDC single sign-on (Keycloak, Authentik, Lemonldap, etc.). Requires the OAUTH_* environment variables to be set."
    )
  end

  def describe(:recaptcha_signup_provider) do
    dgettext(
      "dashboard_admin",
      "Bot-protection provider for the public signup form. Google requires RECAPTCHA_SITE_KEY and RECAPTCHA_SECRET_KEY; Cloudflare requires TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY, set in the environment - when the selected provider's keys are missing, the choice is honoured but verification is silently skipped."
    )
  end

  def describe(:recaptcha_booking_provider) do
    dgettext(
      "dashboard_admin",
      "Bot-protection provider for the public booking form. Google requires RECAPTCHA_SITE_KEY and RECAPTCHA_SECRET_KEY; Cloudflare requires TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY, set in the environment - when the selected provider's keys are missing, the choice is honoured but verification is silently skipped."
    )
  end

  def describe(:recaptcha_signup_min_score) do
    dgettext(
      "dashboard_admin",
      "Minimum reCAPTCHA v3 score (0.0–1.0) required to accept a signup. Lower values are more permissive; 0.3 is the default and matches Google's recommendation for forms with low abuse risk."
    )
  end

  def describe(:recaptcha_booking_min_score) do
    dgettext(
      "dashboard_admin",
      "Minimum reCAPTCHA v3 score (0.0–1.0) required to accept a booking. Lower values are more permissive; 0.3 is the default and matches Google's recommendation for forms with low abuse risk."
    )
  end

  def describe(:admin_alerts_enabled) do
    dgettext(
      "dashboard_admin",
      "Email operational alerts (webhook failures, integration health issues, background job errors) to the admin alert recipient. Requires a recipient address to be set below."
    )
  end

  def describe(:admin_alert_email) do
    dgettext(
      "dashboard_admin",
      "Email address that receives admin alerts when the toggle above is enabled. Leave blank to fall back to the ADMIN_ALERT_EMAIL environment variable."
    )
  end

  def describe(:meeting_payments_enabled) do
    dgettext(
      "dashboard_admin",
      "Let hosts on this instance take payment from bookers via Stripe Connect. Requires STRIPE_SECRET_KEY and STRIPE_CONNECT_WEBHOOK_SECRET to be set in the environment - without them the toggle stays locked."
    )
  end

  def describe(:booking_analytics_enabled) do
    dgettext(
      "dashboard_admin",
      "Collect privacy-friendly analytics for booking pages on this instance: page views, traffic source (UTM/referrer), and conversion. Counts unique visitors with a daily-rotating, cookieless fingerprint - no raw IP is stored. Off by default; review your privacy policy before enabling."
    )
  end

  def describe(:email_brand_accent) do
    dgettext(
      "dashboard_admin",
      "Accent colour used across transactional emails: buttons, links, the confirmation banner, and badge backgrounds. The darker and lighter shades of the family are derived from it. Amber and red are not affected - they signal \"needs attention\" and \"cancelled\", and recolouring them would make a cancellation read as a confirmation. Leave blank for the stock turquoise."
    )
  end

  def describe(:email_brand_name) do
    dgettext(
      "dashboard_admin",
      "Name shown in the inbox preview line, the logo's alt text, and the email title. Does not change the sender name - set EMAIL_FROM_NAME for that. Leave blank to use \"%{app_name}\".",
      app_name: Config.app_name()
    )
  end

  def describe(:email_logo_path) do
    dgettext(
      "dashboard_admin",
      "Logo shown at the top of every transactional email. Converted to a PNG in your browser before upload and attached inline, so it renders even in clients that block remote images. SVG, PNG, JPEG, and WebP sources are all accepted."
    )
  end

  def describe(:admin_default_locale) do
    dgettext(
      "dashboard_admin",
      "Language the dashboard, account pages, and account emails fall back to. Detection still comes first: a signed-in user's own language setting and the browser's Accept-Language header both win, and this is only what resolves when neither offers a language this install supports. Left unset it resolves to %{language}, this install's configured default.",
      language: default_locale_name()
    )
  end

  def describe(:booking_default_locale) do
    dgettext(
      "dashboard_admin",
      "Language public booking pages fall back to, along with booking emails and calendar invites for an attendee whose language is unknown. Detection still comes first: a visitor whose browser asks for a language this install supports gets that language regardless of this setting. Left unset it resolves to %{language}, this install's configured default.",
      language: default_locale_name()
    )
  end

  def describe(:max_image_upload_size_mb) do
    dgettext(
      "dashboard_admin",
      "Maximum file size, in megabytes, accepted when a host uploads a custom background image in theme customization."
    )
  end

  def describe(:max_video_upload_size_mb) do
    dgettext(
      "dashboard_admin",
      "Maximum file size, in megabytes, accepted when a host uploads a custom background video in theme customization."
    )
  end

  def describe(:booking_attachment_types) do
    dgettext(
      "dashboard_admin",
      "File types a booker may attach on the booking page, for meeting types where the host has switched attachments on. Each file's content is checked against its type. Deselect every type to switch attachments off for the whole install."
    )
  end

  def describe(:max_booking_attachment_size_mb) do
    dgettext(
      "dashboard_admin",
      "Maximum size, in megabytes, of each attached file (at most 100). The files are also attached to the host's booking email when together they stay under 15 MB; larger ones are only downloadable from the dashboard."
    )
  end

  def describe(:max_booking_attachments) do
    dgettext(
      "dashboard_admin",
      "How many files one booking may carry (at most 10)."
    )
  end

  def describe(:audit_log_retention_days) do
    dgettext(
      "dashboard_admin",
      "Security and payment events (sign-ins, account changes, admin actions, payments) are kept in the audit log for this many days, then deleted. They include IP addresses, so keep this no longer than you need."
    )
  end

  def describe(:audit_log_events) do
    dgettext("dashboard_admin", "Which kinds of events are kept in the audit log.")
  end

  def describe(:site_banner_app_enabled) do
    dgettext(
      "dashboard_admin",
      "Show the banner across the dashboard, the admin panel, and onboarding."
    )
  end

  def describe(:site_banner_auth_enabled) do
    dgettext(
      "dashboard_admin",
      "Show the banner on the sign-in, sign-up, and password-reset pages."
    )
  end

  def describe(:site_banner_public_enabled) do
    dgettext(
      "dashboard_admin",
      "Show the banner on every host's public booking pages. It is never shown when a booking page is embedded on another site."
    )
  end

  def describe(:site_banner_message) do
    dgettext(
      "dashboard_admin",
      "One short line shown at the very top of the page. Basic formatting is allowed: links, bold, italic, underline, line breaks, and a class attribute on each. Anything else, including scripts and inline styles, is removed. Classes only take effect if the page's stylesheet already contains them. Visitors can dismiss the banner; editing the message or colour shows it to everyone again. Leave blank to hide the banner everywhere."
    )
  end

  def describe(:site_banner_colour) do
    dgettext(
      "dashboard_admin",
      "Background colour of the banner. The text switches between white and near-black automatically, whichever reads better. Leave blank for the stock dark turquoise."
    )
  end

  def describe(_other), do: ""

  @doc """
  The recommended value for a setting, or `nil` if there is no recommendation.
  Rendered as a separate chip beneath the description.
  """
  @spec recommended(atom()) :: term() | nil
  def recommended(:registration_enabled), do: true
  def recommended(:password_auth_enabled), do: true
  def recommended(_other), do: nil

  @doc "Human-readable label for a recommended boolean value."
  @spec recommended_label(boolean()) :: String.t()
  def recommended_label(true), do: dgettext("dashboard_admin", "Enabled")
  def recommended_label(false), do: dgettext("dashboard_admin", "Disabled")

  @doc """
  Label for the "no override" option: the locale a cleared setting actually
  falls back to, named rather than described.

  Not called "Automatic", because detection runs either way - that word would
  describe the whole resolution chain rather than this one option in it. And
  not left as a bare "instance default": that value comes from `:locales` in
  the application config, so it is neither visible nor changeable from this
  page, and naming it is the only way the option means anything to an admin.
  """
  @spec unset_locale_label() :: String.t()
  def unset_locale_label do
    dgettext("dashboard_admin", "Install default (%{language})", language: default_locale_name())
  end

  defp default_locale_name do
    code = Locales.default_locale()

    case Enum.find(Locales.supported(), &(&1.code == code)) do
      %{name: name} -> name
      nil -> code
    end
  end

  @doc """
  Categorises a setting key so the UI knows which control to render.

    * `:boolean` — two-state Enabled/Disabled toggle (existing pattern).
    * `:score` — numeric input bounded 0.0–1.0 (reCAPTCHA thresholds).
    * `:email` — text input with email validation.
    * `:colour` — hex colour input with a native swatch picker.
    * `:text` — free-text input.
    * `:html` — multi-line input for a short allow-listed HTML snippet
      (the site banner message).
    * `:translations` — per-locale overrides of another setting, edited
      through that setting's own language tabs rather than a row of their
      own (the site banner message's translations).
    * `:logo` — image upload with a preview and a remove action.
    * `:locale` — select over the supported languages, with a blank option
      meaning "no override".
    * `:size_mb` — whole-number input, in megabytes (upload size limits).
    * `:days` — whole-number input, in days (audit log retention).
    * `:attachment_size_mb` — whole-number input, in megabytes, with the
      lower ceiling booker attachments allow.
    * `:file_count` — whole-number input, a number of files.
    * `:attachment_types` — one pill per supported file type, rendered by
      `TymeslotWeb.Dashboard.Admin.BookingAttachmentRows` rather than the
      generic row.
    * `:audit_events` — per-category on/off switches, rendered by
      `TymeslotWeb.Dashboard.Admin.AuditEventRows` rather than one row.
    * `:provider` — three-state Off/Google/Cloudflare pill selector
      (bot-protection provider).
  """
  @spec kind(atom()) ::
          :boolean
          | :score
          | :email
          | :colour
          | :text
          | :html
          | :translations
          | :logo
          | :locale
          | :size_mb
          | :days
          | :attachment_size_mb
          | :file_count
          | :attachment_types
          | :audit_events
          | :provider
  def kind(:recaptcha_signup_provider), do: :provider
  def kind(:recaptcha_booking_provider), do: :provider
  def kind(:recaptcha_signup_min_score), do: :score
  def kind(:recaptcha_booking_min_score), do: :score
  def kind(:admin_alert_email), do: :email
  def kind(:email_brand_accent), do: :colour
  def kind(:email_brand_name), do: :text
  def kind(:email_logo_path), do: :logo
  def kind(:admin_default_locale), do: :locale
  def kind(:booking_default_locale), do: :locale
  def kind(:max_image_upload_size_mb), do: :size_mb
  def kind(:max_video_upload_size_mb), do: :size_mb
  def kind(:booking_attachment_types), do: :attachment_types
  def kind(:max_booking_attachment_size_mb), do: :attachment_size_mb
  def kind(:max_booking_attachments), do: :file_count
  def kind(:audit_log_retention_days), do: :days
  def kind(:audit_log_events), do: :audit_events
  def kind(:site_banner_message), do: :html
  def kind(:site_banner_colour), do: :colour
  def kind(:site_banner_translations), do: :translations
  def kind(_other), do: :boolean

  @doc """
  Section heading a setting row belongs under. Used to group the settings
  page into Authentication / reCAPTCHA / Admin alerts blocks.
  """
  @spec section(atom()) ::
          :authentication
          | :recaptcha
          | :payments
          | :analytics
          | :uploads
          | :booking_attachments
          | :audit_log
          | :audit_events
          | :admin_alerts
          | :email_branding
          | :localisation
          | :site_banner
  def section(:registration_enabled), do: :authentication
  def section(:password_auth_enabled), do: :authentication
  def section(:google_auth_enabled), do: :authentication
  def section(:github_auth_enabled), do: :authentication
  def section(:microsoft_auth_enabled), do: :authentication
  def section(:oauth_auth_enabled), do: :authentication
  def section(:recaptcha_signup_provider), do: :recaptcha
  def section(:recaptcha_booking_provider), do: :recaptcha
  def section(:recaptcha_signup_min_score), do: :recaptcha
  def section(:recaptcha_booking_min_score), do: :recaptcha
  def section(:meeting_payments_enabled), do: :payments
  def section(:booking_analytics_enabled), do: :analytics
  def section(:max_image_upload_size_mb), do: :uploads
  def section(:max_video_upload_size_mb), do: :uploads
  def section(:booking_attachment_types), do: :booking_attachments
  def section(:max_booking_attachment_size_mb), do: :booking_attachments
  def section(:max_booking_attachments), do: :booking_attachments
  def section(:audit_log_retention_days), do: :audit_log
  def section(:audit_log_events), do: :audit_events
  def section(:admin_alerts_enabled), do: :admin_alerts
  def section(:admin_alert_email), do: :admin_alerts
  def section(:email_brand_accent), do: :email_branding
  def section(:email_brand_name), do: :email_branding
  def section(:email_logo_path), do: :email_branding
  def section(:admin_default_locale), do: :localisation
  def section(:booking_default_locale), do: :localisation
  def section(:site_banner_app_enabled), do: :site_banner
  def section(:site_banner_auth_enabled), do: :site_banner
  def section(:site_banner_public_enabled), do: :site_banner
  def section(:site_banner_message), do: :site_banner
  def section(:site_banner_colour), do: :site_banner
  def section(:site_banner_translations), do: :site_banner

  @doc "Human-readable label for a section."
  @spec section_label(atom()) :: String.t()
  def section_label(:authentication), do: dgettext("dashboard_admin", "Authentication")
  def section_label(:recaptcha), do: dgettext("dashboard_admin", "Bot protection")
  def section_label(:payments), do: dgettext("dashboard_admin", "Payments")
  def section_label(:analytics), do: dgettext("dashboard_admin", "Analytics")
  def section_label(:uploads), do: dgettext("dashboard_admin", "Uploads")

  def section_label(:booking_attachments),
    do: dgettext("dashboard_admin", "Booking attachments")

  def section_label(:audit_log), do: dgettext("dashboard_admin", "Retention")
  def section_label(:audit_events), do: dgettext("dashboard_admin", "Logged events")
  def section_label(:admin_alerts), do: dgettext("dashboard_admin", "Admin alerts")
  def section_label(:email_branding), do: dgettext("dashboard_admin", "Email branding")
  def section_label(:localisation), do: dgettext("dashboard_admin", "Localisation")
  def section_label(:site_banner), do: dgettext("dashboard_admin", "Site banner")

  @doc """
  When a setting is only meaningful while another setting is enabled, this
  returns the parent setting key — otherwise `nil`. The UI greys out and
  disables the dependent control when the parent's effective value is `false`.

  Example: `admin_alert_email` is meaningless while `admin_alerts_enabled`
  is off, so the recipient input is disabled until alerts are turned on.
  """
  @spec depends_on(atom()) :: atom() | nil
  def depends_on(:admin_alert_email), do: :admin_alerts_enabled
  def depends_on(_other), do: nil

  @doc """
  Explanation shown to an admin for why a particular setting state is
  currently locked. Returns `nil` when the transition is not blocked. The
  string is used both as a tooltip on the disabled toggle and as the flash
  message when a race-conditioned write reaches `AppSettings.update/1`.
  """
  @spec lock_reason(atom(), term()) :: String.t() | nil
  def lock_reason(:password_auth_enabled, false) do
    dgettext(
      "dashboard_admin",
      "Cannot disable password authentication while at least one admin signs in with email and password - doing so would lock them out. Demote those admins or have them switch to an OAuth login first."
    )
  end

  def lock_reason(:google_auth_enabled, false), do: sso_lock_reason()
  def lock_reason(:github_auth_enabled, false), do: sso_lock_reason()
  def lock_reason(:microsoft_auth_enabled, false), do: sso_lock_reason()
  def lock_reason(:oauth_auth_enabled, false), do: sso_lock_reason()

  def lock_reason(:meeting_payments_enabled, true) do
    dgettext(
      "dashboard_admin",
      "Set STRIPE_SECRET_KEY and STRIPE_CONNECT_WEBHOOK_SECRET in the environment to enable meeting payments. Without platform credentials the Stripe Connect onboarding flow cannot start."
    )
  end

  def lock_reason(_key, _state), do: nil

  defp sso_lock_reason do
    dgettext(
      "dashboard_admin",
      "Cannot disable this login provider while it is the only working sign-in path for admins. Enable password authentication or another credentialed SSO provider first."
    )
  end
end
