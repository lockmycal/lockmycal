defmodule Tymeslot.Infrastructure.Security.BotProtectionTest do
  use ExUnit.Case, async: false

  @moduletag :infrastructure

  alias Tymeslot.Infrastructure.Security.BotProtection

  setup do
    old_cfg = Application.get_env(:tymeslot, :recaptcha, [])
    old_recaptcha_site_key = System.get_env("RECAPTCHA_SITE_KEY")
    old_recaptcha_secret_key = System.get_env("RECAPTCHA_SECRET_KEY")
    old_turnstile_site_key = System.get_env("TURNSTILE_SITE_KEY")
    old_turnstile_secret_key = System.get_env("TURNSTILE_SECRET_KEY")

    on_exit(fn ->
      Application.put_env(:tymeslot, :recaptcha, old_cfg)
      restore_env("RECAPTCHA_SITE_KEY", old_recaptcha_site_key)
      restore_env("RECAPTCHA_SECRET_KEY", old_recaptcha_secret_key)
      restore_env("TURNSTILE_SITE_KEY", old_turnstile_site_key)
      restore_env("TURNSTILE_SECRET_KEY", old_turnstile_secret_key)
    end)

    :ok
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp set_provider(scope, provider) do
    key = if scope == :signup, do: :signup_provider, else: :booking_provider
    cfg = Application.get_env(:tymeslot, :recaptcha, [])
    Application.put_env(:tymeslot, :recaptcha, Keyword.put(cfg, key, provider))
  end

  describe "signup_provider/0 and booking_provider/0" do
    test "default to :off when unset" do
      Application.put_env(:tymeslot, :recaptcha, [])
      assert BotProtection.signup_provider() == :off
      assert BotProtection.booking_provider() == :off
    end

    test "reflect the configured value" do
      set_provider(:signup, :google)
      set_provider(:booking, :cloudflare)

      assert BotProtection.signup_provider() == :google
      assert BotProtection.booking_provider() == :cloudflare
    end
  end

  describe "active?/1" do
    test "false when provider is :off" do
      set_provider(:signup, :off)
      refute BotProtection.active?(:signup)
    end

    test "false when provider is selected but its keys are missing" do
      set_provider(:signup, :google)
      System.delete_env("RECAPTCHA_SITE_KEY")
      System.delete_env("RECAPTCHA_SECRET_KEY")
      refute BotProtection.active?(:signup)
    end

    test "true when Google is selected and its keys are present" do
      set_provider(:signup, :google)
      System.put_env("RECAPTCHA_SITE_KEY", "site")
      System.put_env("RECAPTCHA_SECRET_KEY", "secret")
      assert BotProtection.active?(:signup)
    end

    test "true when Cloudflare is selected and its keys are present" do
      set_provider(:booking, :cloudflare)
      System.put_env("TURNSTILE_SITE_KEY", "site")
      System.put_env("TURNSTILE_SECRET_KEY", "secret")
      assert BotProtection.active?(:booking)
    end
  end

  describe "token_param_name/1" do
    test "is the reCAPTCHA field for :off and :google" do
      set_provider(:signup, :off)
      assert BotProtection.token_param_name(:signup) == "g-recaptcha-response"

      set_provider(:signup, :google)
      assert BotProtection.token_param_name(:signup) == "g-recaptcha-response"
    end

    test "is the Turnstile field for :cloudflare" do
      set_provider(:booking, :cloudflare)
      assert BotProtection.token_param_name(:booking) == "cf-turnstile-response"
    end
  end

  describe "hook_name/1" do
    test "picks the right client-side hook per provider" do
      set_provider(:signup, :google)
      assert BotProtection.hook_name(:signup) == "RecaptchaV3"

      set_provider(:signup, :cloudflare)
      assert BotProtection.hook_name(:signup) == "Turnstile"
    end
  end

  describe "maybe_verify_signup_token/2 and maybe_verify_booking_token/2" do
    test "no-op :ok when the provider is :off" do
      set_provider(:signup, :off)
      set_provider(:booking, :off)

      assert BotProtection.maybe_verify_signup_token("", %{}) == :ok
      assert BotProtection.maybe_verify_booking_token(nil, %{}) == :ok
    end

    test "fails open to :ok when Google is selected but keys are missing" do
      set_provider(:signup, :google)
      System.delete_env("RECAPTCHA_SITE_KEY")
      System.delete_env("RECAPTCHA_SECRET_KEY")

      assert BotProtection.maybe_verify_signup_token("some-token", %{}) == :ok
    end

    test "fails open to :ok when Cloudflare is selected but keys are missing" do
      set_provider(:booking, :cloudflare)
      System.delete_env("TURNSTILE_SITE_KEY")
      System.delete_env("TURNSTILE_SECRET_KEY")

      assert BotProtection.maybe_verify_booking_token("some-token", %{}) == :ok
    end

    test "rejects an empty token when Google is active and configured" do
      set_provider(:signup, :google)
      System.put_env("RECAPTCHA_SITE_KEY", "site")
      System.put_env("RECAPTCHA_SECRET_KEY", "secret")

      assert BotProtection.maybe_verify_signup_token("", %{}) == {:error, :recaptcha_failed}
    end

    test "rejects an empty token when Cloudflare is active and configured" do
      set_provider(:booking, :cloudflare)
      System.put_env("TURNSTILE_SITE_KEY", "site")
      System.put_env("TURNSTILE_SECRET_KEY", "secret")

      assert BotProtection.maybe_verify_booking_token("", %{}) == {:error, :recaptcha_failed}
    end
  end
end
