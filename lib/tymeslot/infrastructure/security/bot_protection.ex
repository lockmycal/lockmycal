defmodule Tymeslot.Infrastructure.Security.BotProtection do
  @moduledoc """
  Single dispatch point for the signup/booking bot-protection gate.

  The signup form and the booking form each independently pick one of
  `:off | :google | :cloudflare` as their anti-bot provider (admin-editable
  via `Tymeslot.AppSettings`, seeded from `RECAPTCHA_SIGNUP_PROVIDER`/
  `RECAPTCHA_BOOKING_PROVIDER` — see `config/runtime.exs`). This module is
  the one place callers (`Tymeslot.Auth.SignupSecurity`, booking guards, poll
  voting, and the theme form components) need to know about — it dispatches
  to `Tymeslot.Infrastructure.Security.RecaptchaHelpers` or
  `Tymeslot.Infrastructure.Security.TurnstileHelpers` so neither of those two
  provider-specific helpers has to know about the other, mirroring how
  `Tymeslot.Security.SsrfGuard` centralizes another cross-cutting security
  concern.
  """

  alias Tymeslot.Infrastructure.Security.RecaptchaHelpers
  alias Tymeslot.Infrastructure.Security.TurnstileHelpers

  @type scope :: :signup | :booking
  @type provider :: :off | :google | :cloudflare

  @doc "Which provider is configured for the signup form."
  @spec signup_provider() :: provider()
  def signup_provider, do: recaptcha_config(:signup_provider)

  @doc "Which provider is configured for the booking form (and poll voting, which shares this gate)."
  @spec booking_provider() :: provider()
  def booking_provider, do: recaptcha_config(:booking_provider)

  @spec provider(scope()) :: provider()
  def provider(:signup), do: signup_provider()
  def provider(:booking), do: booking_provider()

  @doc "True when a provider is selected for this scope and its keys are actually configured."
  @spec active?(scope()) :: boolean()
  def active?(:signup), do: RecaptchaHelpers.signup_active?() or TurnstileHelpers.signup_active?()

  def active?(:booking),
    do: RecaptchaHelpers.booking_active?() or TurnstileHelpers.booking_active?()

  @doc "The request-param key the active provider's token arrives under (nested under the form's param root)."
  @spec token_param_name(scope()) :: String.t()
  def token_param_name(scope) do
    case provider(scope) do
      :cloudflare -> "cf-turnstile-response"
      _google_or_off -> "g-recaptcha-response"
    end
  end

  @doc "The public site key the browser widget needs, for whichever provider is active."
  @spec site_key(scope()) :: String.t() | nil
  def site_key(scope) do
    case provider(scope) do
      :cloudflare -> TurnstileHelpers.site_key()
      _google_or_off -> RecaptchaHelpers.site_key()
    end
  end

  @doc "The verification action name the active provider expects for this scope."
  @spec action(scope()) :: String.t() | nil
  def action(:signup) do
    case signup_provider() do
      :cloudflare -> TurnstileHelpers.signup_action()
      _google_or_off -> RecaptchaHelpers.signup_action()
    end
  end

  def action(:booking) do
    case booking_provider() do
      :cloudflare -> TurnstileHelpers.booking_action()
      _google_or_off -> RecaptchaHelpers.booking_action()
    end
  end

  @doc "The Phoenix LiveView `phx-hook` name for the active provider's client-side widget."
  @spec hook_name(scope()) :: String.t()
  def hook_name(scope) do
    case provider(scope) do
      :cloudflare -> "Turnstile"
      _google_or_off -> "RecaptchaV3"
    end
  end

  @doc """
  Verifies the signup form's token against whichever provider is configured.

  Returns `:ok` when protection is off, or the underlying helper's result
  (`:ok`, `{:error, :recaptcha_failed}`, or `{:error, :recaptcha_script_blocked}`)
  otherwise.
  """
  @spec maybe_verify_signup_token(String.t(), map()) ::
          :ok | {:error, :recaptcha_failed} | {:error, :recaptcha_script_blocked}
  def maybe_verify_signup_token(token, metadata \\ %{}) do
    case signup_provider() do
      :cloudflare -> TurnstileHelpers.maybe_verify_signup_token(token, metadata)
      :google -> RecaptchaHelpers.maybe_verify_signup_token(token, metadata)
      :off -> :ok
    end
  end

  @doc "Same as `maybe_verify_signup_token/2`, for the booking form (and poll voting)."
  @spec maybe_verify_booking_token(String.t() | nil, map()) ::
          :ok | {:error, :recaptcha_failed} | {:error, :recaptcha_script_blocked}
  def maybe_verify_booking_token(token, metadata \\ %{}) do
    case booking_provider() do
      :cloudflare -> TurnstileHelpers.maybe_verify_booking_token(token, metadata)
      :google -> RecaptchaHelpers.maybe_verify_booking_token(token, metadata)
      :off -> :ok
    end
  end

  defp recaptcha_config(key) do
    :tymeslot
    |> Application.get_env(:recaptcha, [])
    |> Keyword.get(key, :off)
  end
end
