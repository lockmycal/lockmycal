defmodule Tymeslot.Infrastructure.Security.TurnstileTest do
  use Tymeslot.DataCase, async: false

  @moduletag :infrastructure

  alias Tymeslot.HTTPClientMock
  alias Tymeslot.Infrastructure.Security.Turnstile
  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    old_client = Application.get_env(:tymeslot, :http_client_module)
    Application.put_env(:tymeslot, :http_client_module, HTTPClientMock)

    original_secret = System.get_env("TURNSTILE_SECRET_KEY")
    System.put_env("TURNSTILE_SECRET_KEY", "test_secret")

    on_exit(fn ->
      if old_client do
        Application.put_env(:tymeslot, :http_client_module, old_client)
      else
        Application.delete_env(:tymeslot, :http_client_module)
      end

      if original_secret do
        System.put_env("TURNSTILE_SECRET_KEY", original_secret)
      else
        System.delete_env("TURNSTILE_SECRET_KEY")
      end
    end)

    :ok
  end

  describe "verify/2" do
    test "returns :ok when Cloudflare returns success" do
      token = "valid_token"

      response_body =
        Jason.encode!(%{
          "success" => true,
          "action" => "login",
          "hostname" => "localhost"
        })

      expect(HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %Req.Response{status: 200, body: response_body}}
      end)

      assert {:ok, %{action: "login", hostname: "localhost"}} = Turnstile.verify(token)
    end

    test "returns :error when action mismatches" do
      token = "token"

      response_body =
        Jason.encode!(%{
          "success" => true,
          "action" => "wrong_action"
        })

      expect(HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %Req.Response{status: 200, body: response_body}}
      end)

      assert {:error, :turnstile_action_mismatch} =
               Turnstile.verify(token, expected_action: "login")
    end

    test "returns :error when hostname mismatches" do
      token = "token"

      response_body =
        Jason.encode!(%{
          "success" => true,
          "hostname" => "wrong.com"
        })

      expect(HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %Req.Response{status: 200, body: response_body}}
      end)

      assert {:error, :turnstile_hostname_mismatch} =
               Turnstile.verify(token, expected_hostnames: ["correct.com"])
    end

    test "returns :error when token is too large" do
      large_token = String.duplicate("a", 5001)
      assert {:error, :invalid_token} = Turnstile.verify(large_token)
    end

    test "returns :error when token is empty or nil" do
      assert {:error, :invalid_token} = Turnstile.verify("")
      assert {:error, :invalid_token} = Turnstile.verify(nil)
    end

    test "returns :error when secret key is missing" do
      System.delete_env("TURNSTILE_SECRET_KEY")
      assert {:error, :turnstile_configuration_error} = Turnstile.verify("token")
    end

    test "handles Cloudflare API returning success: false" do
      token = "invalid_token"

      response_body =
        Jason.encode!(%{
          "success" => false,
          "error-codes" => ["invalid-input-response"]
        })

      expect(HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
        {:ok, %Req.Response{status: 200, body: response_body}}
      end)

      assert {:error, :turnstile_verification_failed} = Turnstile.verify(token)
    end

    test "handles network errors" do
      expect(HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
        {:error, %RuntimeError{message: "Network error"}}
      end)

      assert {:error, :turnstile_network_error} = Turnstile.verify("token")
    end
  end

  describe "maybe_put_remote_ip/2" do
    test "adds remoteip when valid IPv4" do
      params = %{"foo" => "bar"}

      assert %{"foo" => "bar", "remoteip" => "1.2.3.4"} =
               Turnstile.maybe_put_remote_ip(params, "1.2.3.4")
    end

    test "does not add remoteip when invalid or blank" do
      params = %{"foo" => "bar"}
      assert ^params = Turnstile.maybe_put_remote_ip(params, "")
      assert ^params = Turnstile.maybe_put_remote_ip(params, "invalid")
      assert ^params = Turnstile.maybe_put_remote_ip(params, "unknown")
      assert ^params = Turnstile.maybe_put_remote_ip(params, "fe80::1%eth0")
    end
  end

  describe "validation helpers" do
    test "validate_expected_action/2" do
      assert :ok = Turnstile.validate_expected_action("signup_form", "signup_form")
      assert :ok = Turnstile.validate_expected_action("anything", nil)

      assert {:error, :turnstile_action_mismatch} =
               Turnstile.validate_expected_action("login_form", "signup_form")

      assert {:error, :turnstile_missing_action} =
               Turnstile.validate_expected_action(nil, "signup_form")
    end

    test "validate_expected_hostname/2" do
      assert :ok = Turnstile.validate_expected_hostname("example.com", [])
      assert :ok = Turnstile.validate_expected_hostname("example.com", ["example.com"])

      assert {:error, :turnstile_hostname_mismatch} =
               Turnstile.validate_expected_hostname("evil.com", ["example.com"])

      assert {:error, :turnstile_missing_hostname} =
               Turnstile.validate_expected_hostname(nil, ["example.com"])
    end
  end
end
