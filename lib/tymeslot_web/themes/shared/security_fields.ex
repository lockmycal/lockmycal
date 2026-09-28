defmodule TymeslotWeb.Themes.Shared.SecurityFields do
  @moduledoc """
  Shared security field components for booking and signup forms.

  Provides honeypot and bot-protection (reCAPTCHA v3 or Cloudflare Turnstile,
  whichever the admin has configured — see
  `Tymeslot.Infrastructure.Security.BotProtection`) fields to prevent spam
  and bot submissions.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Security.BotProtection

  @doc """
  Renders a honeypot field to catch automated bot submissions.

  The field is hidden from real users using absolute positioning (not sr-only)
  and aria-hidden to prevent screen reader announcement. The field uses:
  - `tabindex="-1"` to prevent keyboard navigation
  - `autocomplete="off"` to prevent browser autofill

  Bots that fill this field will be silently rejected with a fake success message.

  ## Parameters

    * `id_prefix` - Prefix for the field ID (e.g., "booking")
    * `param_root` - Root parameter name (e.g., "booking" for booking[website])
  """
  attr :id_prefix, :string, required: true
  attr :param_root, :string, required: true

  @spec honeypot_field(map()) :: Phoenix.LiveView.Rendered.t()
  def honeypot_field(assigns) do
    ~H"""
    <%!-- Honeypot field (hidden from real users, visible to bots) --%>
    <div class="honeypot-field" aria-hidden="true">
      <label for={"#{@id_prefix}-website"}>Website</label>
      <input
        id={"#{@id_prefix}-website"}
        type="text"
        name={"#{@param_root}[website]"}
        tabindex="-1"
        autocomplete="off"
        value=""
      />
    </div>
    """
  end

  @doc """
  Renders bot-protection fields and privacy notice if a provider is active.

  Includes:
  - Hidden input field for the provider's verification token (plus a widget
    container when Cloudflare Turnstile is the active provider)
  - Privacy notice with links to the active provider's Privacy Policy and
    Terms of Service

  Only renders if a provider is selected for `scope` and properly configured
  with keys.

  ## Parameters

    * `id_prefix` - Prefix for the field ID (e.g., "booking")
    * `param_root` - Root parameter name (e.g., "booking")
    * `scope` - `:booking` (default) or `:signup` — which form's configured
      provider/action/gettext domain to use
  """
  attr :id_prefix, :string, required: true
  attr :param_root, :string, required: true
  attr :scope, :atom, default: :booking

  @spec recaptcha_fields(map()) :: Phoenix.LiveView.Rendered.t()
  def recaptcha_fields(assigns) do
    ~H"""
    <.recaptcha_token_field id_prefix={@id_prefix} param_root={@param_root} scope={@scope} />
    <.recaptcha_notice_block scope={@scope} />
    """
  end

  @doc """
  Renders only the hidden bot-protection token input (no notice), plus a
  Turnstile widget container when Cloudflare is the active provider.

  Use this inside the booking/signup `<.form>` when the privacy notice needs
  to be positioned separately (e.g. below a sibling field). Pair with
  `recaptcha_notice_block/1`.
  """
  attr :id_prefix, :string, required: true
  attr :param_root, :string, required: true
  attr :scope, :atom, default: :booking

  @spec recaptcha_token_field(map()) :: Phoenix.LiveView.Rendered.t()
  def recaptcha_token_field(assigns) do
    assigns = assign(assigns, :provider, BotProtection.provider(assigns.scope))

    ~H"""
    <input
      :if={BotProtection.active?(@scope)}
      type="hidden"
      name={"#{@param_root}[#{BotProtection.token_param_name(@scope)}]"}
      id={"#{@id_prefix}-#{BotProtection.token_param_name(@scope)}"}
      value=""
    />
    <div
      :if={@provider == :cloudflare and BotProtection.active?(@scope)}
      id={"#{@id_prefix}-cf-turnstile"}
    />
    """
  end

  @doc """
  Renders only the bot-protection privacy notice (no hidden input).

  Position this wherever the notice should appear in the layout; the token
  input from `recaptcha_token_field/1` must still live inside the form.
  """
  attr :scope, :atom, default: :booking

  @spec recaptcha_notice_block(map()) :: Phoenix.LiveView.Rendered.t()
  def recaptcha_notice_block(assigns) do
    ~H"""
    <div
      :if={BotProtection.active?(@scope)}
      class="recaptcha-notice text-xs text-neutral-500 text-center"
    >
      {Phoenix.HTML.raw(recaptcha_notice(@scope))}
    </div>
    """
  end

  defp recaptcha_notice(scope) do
    case BotProtection.provider(scope) do
      :cloudflare -> turnstile_notice(scope)
      _google_or_off -> google_notice(scope)
    end
  end

  # Placeholder names in the wrapping sentence differ by domain (`privacy_link`/
  # `terms_link` for "booking", `privacy_policy`/`terms` for "auth") to match
  # each domain's pre-existing msgid exactly — booking's own notice predates
  # this module's Turnstile support, and signup's was inlined in
  # `SignupComponent` before being moved here; preserving both keeps their
  # already-translated strings intact instead of orphaning them.
  defp google_notice(:booking) do
    dgettext(
      "booking",
      "This site is protected by reCAPTCHA and the Google %{privacy_link} and %{terms_link} apply.",
      privacy_link: booking_policy_link("https://policies.google.com/privacy"),
      terms_link: booking_terms_link("https://policies.google.com/terms")
    )
  end

  defp google_notice(:signup) do
    dgettext(
      "auth",
      "This site is protected by reCAPTCHA and the Google %{privacy_policy} and %{terms} apply.",
      privacy_policy: signup_policy_link("https://policies.google.com/privacy"),
      terms: signup_terms_link("https://policies.google.com/terms")
    )
  end

  defp turnstile_notice(:booking) do
    dgettext(
      "booking",
      "This site is protected by Cloudflare Turnstile and the Cloudflare %{privacy_link} and %{terms_link} apply.",
      privacy_link: booking_policy_link("https://www.cloudflare.com/privacypolicy/"),
      terms_link: booking_terms_link("https://www.cloudflare.com/website-terms/")
    )
  end

  defp turnstile_notice(:signup) do
    dgettext(
      "auth",
      "This site is protected by Cloudflare Turnstile and the Cloudflare %{privacy_policy} and %{terms} apply.",
      privacy_policy: signup_policy_link("https://www.cloudflare.com/privacypolicy/"),
      terms: signup_terms_link("https://www.cloudflare.com/website-terms/")
    )
  end

  @link_class "text-primary-600 underline hover:text-primary-700"

  # `dgettext/2`'s domain must be a compile-time literal (it's a macro that
  # extracts msgids per domain at compile time), so each domain gets its own
  # clause here rather than a single function taking the domain at runtime.
  defp booking_policy_link(href), do: link_tag(href, dgettext("booking", "Privacy Policy"))
  defp booking_terms_link(href), do: link_tag(href, dgettext("booking", "Terms of Service"))
  defp signup_policy_link(href), do: link_tag(href, dgettext("auth", "Privacy Policy"))
  defp signup_terms_link(href), do: link_tag(href, dgettext("auth", "Terms of Service"))

  defp link_tag(href, label) do
    ~s(<a href="#{href}" target="_blank" rel="noopener noreferrer" class="#{@link_class}">) <>
      label <> "</a>"
  end

  @doc """
  Returns map of bot-protection data attributes for form element if active.

  Use this on the form tag to enable reCAPTCHA v3 or Turnstile via their
  respective hooks.

  ## Example

      <.form
        for={@form}
        phx-submit="submit"
        {recaptcha_form_attrs("booking_form", "booking")}
      >
  """
  @spec recaptcha_form_attrs(String.t(), String.t(), BotProtection.scope()) :: map()
  def recaptcha_form_attrs(action, param_root, scope \\ :booking) do
    if BotProtection.active?(scope) do
      %{
        :"data-site-key" => BotProtection.site_key(scope),
        :"data-recaptcha-action" => action,
        :"data-recaptcha-event" => "submit",
        :"data-recaptcha-param-root" => param_root,
        :"data-recaptcha-require-token" => "true",
        :"phx-hook" => BotProtection.hook_name(scope)
      }
    else
      %{}
    end
  end
end
