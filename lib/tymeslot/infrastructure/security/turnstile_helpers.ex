defmodule Tymeslot.Infrastructure.Security.TurnstileHelpers do
  @moduledoc """
  Helper functions for Cloudflare Turnstile integration.

  Mirrors `Tymeslot.Infrastructure.Security.RecaptchaHelpers`'s shape — see
  that module for the enabled/active/gate pattern this repeats. The provider
  selection itself (`:off | :google | :cloudflare`) lives in the shared
  `:recaptcha` app-env keyword list read here and in `RecaptchaHelpers`, so
  `Tymeslot.Infrastructure.Security.BotProtection` can dispatch to whichever
  helper matches the configured provider without either helper depending on
  the other.
  """

  alias Tymeslot.Infrastructure.Security.Turnstile
  require Logger

  @doc """
  Returns the Turnstile site key from environment variables.
  """
  @spec site_key() :: String.t() | nil
  def site_key do
    System.get_env("TURNSTILE_SITE_KEY")
  end

  @spec secret_key() :: String.t() | nil
  def secret_key do
    System.get_env("TURNSTILE_SECRET_KEY")
  end

  @doc """
  Whether Cloudflare Turnstile is the configured provider for signup.

  This is a *feature flag*; if selected but keys are missing, signup
  verification is automatically disabled (and logged) so legitimate signups
  aren't blocked by misconfiguration.
  """
  @spec signup_enabled?() :: boolean()
  def signup_enabled? do
    recaptcha_provider(:signup_provider) == :cloudflare
  end

  @spec signup_action() :: String.t() | nil
  def signup_action do
    turnstile_cfg = Application.get_env(:tymeslot, :turnstile, [])
    Keyword.get(turnstile_cfg, :signup_action)
  end

  @spec expected_hostnames() :: [String.t()]
  def expected_hostnames do
    turnstile_cfg = Application.get_env(:tymeslot, :turnstile, [])
    Keyword.get(turnstile_cfg, :expected_hostnames, [])
  end

  @spec signup_active?() :: boolean()
  def signup_active? do
    signup_enabled?() and key_present?(site_key()) and key_present?(secret_key())
  end

  @doc """
  Whether Cloudflare Turnstile is the configured provider for booking.

  This is a *feature flag*; if selected but keys are missing, booking
  verification is automatically disabled (and logged) so legitimate bookings
  aren't blocked by misconfiguration.
  """
  @spec booking_enabled?() :: boolean()
  def booking_enabled? do
    recaptcha_provider(:booking_provider) == :cloudflare
  end

  @spec booking_action() :: String.t() | nil
  def booking_action do
    turnstile_cfg = Application.get_env(:tymeslot, :turnstile, [])
    Keyword.get(turnstile_cfg, :booking_action)
  end

  @spec booking_active?() :: boolean()
  def booking_active? do
    booking_enabled?() and key_present?(site_key()) and key_present?(secret_key())
  end

  @doc """
  Verify signup token if Cloudflare is the configured provider and configured.

  Returns:
  - `:ok` when Cloudflare isn't the configured provider, or when verification passes
  - `{:error, :recaptcha_failed}` when configured but verification fails
  - `{:error, :recaptcha_script_blocked}` when the Turnstile script failed to load
  """
  @spec maybe_verify_signup_token(String.t(), map()) ::
          :ok | {:error, :recaptcha_failed} | {:error, :recaptcha_script_blocked}
  def maybe_verify_signup_token(token, metadata \\ %{})

  def maybe_verify_signup_token(token, metadata) do
    cond do
      not signup_enabled?() ->
        :ok

      not signup_active?() ->
        log_signup_disabled_due_to_missing_keys(metadata)
        :ok

      true ->
        verify_signup_token_impl(token, metadata)
    end
  end

  # Special marker: Turnstile script failed to load (CSP, extension, JS disabled)
  defp verify_signup_token_impl("TURNSTILE_SCRIPT_BLOCKED", metadata) do
    Logger.warning("Signup attempted with Turnstile script blocked",
      event: "signup_turnstile_script_blocked",
      ip: metadata[:ip],
      user_agent: metadata[:user_agent],
      hint:
        "Check: JavaScript disabled, browser extension, or Content-Security-Policy blocking Turnstile"
    )

    {:error, :recaptcha_script_blocked}
  end

  defp verify_signup_token_impl(token, metadata) do
    case Turnstile.verify(token,
           expected_action: signup_action(),
           expected_hostnames: expected_hostnames(),
           remote_ip: metadata[:ip]
         ) do
      {:ok, %{action: action, hostname: hostname}} ->
        Logger.info("Signup Turnstile passed",
          event: "signup_turnstile_passed",
          action: action,
          hostname: hostname,
          ip: metadata[:ip],
          user_agent: metadata[:user_agent]
        )

        :ok

      {:error, reason} ->
        Logger.warning("Signup Turnstile failed",
          event: "signup_turnstile_failed",
          reason: reason,
          ip: metadata[:ip],
          user_agent: metadata[:user_agent]
        )

        {:error, :recaptcha_failed}
    end
  end

  @doc """
  Verify booking token if Cloudflare is the configured provider and configured.

  Accepts nil or empty tokens and handles them appropriately based on whether
  Turnstile is the active provider.

  ## Parameters

    * `token` - Turnstile token from client (may be nil, empty, or a valid token)
    * `metadata` - Map containing `:ip` and `:user_agent` for logging (optional)

  ## Returns

  - `:ok` when Cloudflare isn't the configured provider, or when verification passes
  - `{:error, :recaptcha_failed}` when configured but verification fails
  - `{:error, :recaptcha_script_blocked}` when the Turnstile script failed to load
  """
  @spec maybe_verify_booking_token(String.t() | nil, map()) ::
          :ok | {:error, :recaptcha_failed} | {:error, :recaptcha_script_blocked}
  def maybe_verify_booking_token(token, metadata \\ %{})

  def maybe_verify_booking_token(token, metadata) do
    cond do
      not booking_enabled?() ->
        :ok

      not booking_active?() ->
        log_booking_disabled_due_to_missing_keys(metadata)
        :ok

      true ->
        verify_booking_token_impl(token, metadata)
    end
  end

  # Special marker: Turnstile script failed to load (CSP, extension, JS disabled)
  defp verify_booking_token_impl("TURNSTILE_SCRIPT_BLOCKED", metadata) do
    Logger.warning("Booking attempted with Turnstile script blocked",
      event: "booking_turnstile_script_blocked",
      ip: metadata[:ip],
      user_agent: metadata[:user_agent],
      hint:
        "Check: JavaScript disabled, browser extension, or Content-Security-Policy blocking Turnstile"
    )

    {:error, :recaptcha_script_blocked}
  end

  defp verify_booking_token_impl(token, metadata) do
    ip = metadata[:ip] || "unknown"
    user_agent = metadata[:user_agent] || "unknown"

    case Turnstile.verify(token,
           expected_action: booking_action(),
           expected_hostnames: expected_hostnames(),
           remote_ip: ip
         ) do
      {:ok, %{action: action, hostname: hostname}} ->
        Logger.info("Booking Turnstile passed",
          event: "booking_turnstile_passed",
          action: action,
          hostname: hostname,
          ip: ip,
          user_agent: user_agent
        )

        :ok

      {:error, reason} ->
        Logger.warning("Booking Turnstile failed",
          event: "booking_turnstile_failed",
          reason: reason,
          ip: ip,
          user_agent: user_agent
        )

        {:error, :recaptcha_failed}
    end
  end

  defp recaptcha_provider(key) do
    :tymeslot
    |> Application.get_env(:recaptcha, [])
    |> Keyword.get(key, :off)
  end

  defp key_present?(value) when is_binary(value), do: String.trim(value) != ""
  defp key_present?(_value), do: false

  # Avoid log spam by emitting at most once per minute per node.
  defp log_signup_disabled_due_to_missing_keys(metadata) do
    now_ms = System.system_time(:millisecond)
    key = {__MODULE__, :signup_disabled_missing_keys_last_logged_at}
    last_ms = :persistent_term.get(key, 0)

    if now_ms - last_ms >= 60_000 do
      :persistent_term.put(key, now_ms)

      Logger.warning(
        "Signup Turnstile is the configured provider but missing keys; signup protection is disabled",
        event: "signup_turnstile_disabled_missing_keys",
        ip: metadata[:ip],
        user_agent: metadata[:user_agent]
      )
    end
  end

  # Avoid log spam by emitting at most once per minute per node.
  # Uses atomics for thread-safe throttling without race conditions.
  defp log_booking_disabled_due_to_missing_keys(metadata) do
    now_sec = System.system_time(:second)
    key = {__MODULE__, :booking_disabled_missing_keys_throttle}

    counter =
      case :persistent_term.get(key, nil) do
        nil ->
          ref = :atomics.new(1, [])
          :atomics.put(ref, 1, 0)
          :persistent_term.put(key, ref)
          ref

        existing ->
          existing
      end

    last_sec = :atomics.get(counter, 1)

    if now_sec - last_sec >= 60 do
      case :atomics.compare_exchange(counter, 1, last_sec, now_sec) do
        :ok ->
          Logger.warning(
            "Booking Turnstile is the configured provider but missing keys; booking protection is disabled",
            event: "booking_turnstile_disabled_missing_keys",
            ip: metadata[:ip] || "unknown",
            user_agent: metadata[:user_agent] || "unknown"
          )

        _race_condition ->
          :ok
      end
    end
  end
end
