defmodule Tymeslot.Infrastructure.Security.Turnstile do
  @moduledoc """
  Cloudflare Turnstile verification module for validating tokens.

  Mirrors `Tymeslot.Infrastructure.Security.Recaptcha`'s shape, minus anything
  score-related — Turnstile's siteverify response is pass/fail only, no
  0.0-1.0 score.
  """

  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Infrastructure.Security.RemoteIpParam

  require Logger

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc """
  Verifies a Turnstile token with Cloudflare's API.
  Returns {:ok, %{action: String.t() | nil, hostname: String.t() | nil}} on
  success or {:error, reason} on failure.
  """
  @type verify_opt ::
          {:expected_action, String.t() | nil}
          | {:expected_hostnames, [String.t()]}
          | {:remote_ip, String.t() | nil}

  @spec verify(String.t(), [verify_opt()]) ::
          {:ok, %{action: String.t() | nil, hostname: String.t() | nil}}
          | {:error, atom()}
  def verify(token, opts \\ [])

  def verify(token, opts) when is_binary(token) and byte_size(token) > 0 do
    # Reject tokens that exceed 5KB (real Turnstile tokens are ~2KB)
    # This prevents DoS attacks with huge token payloads
    if byte_size(token) > 5_000 do
      Logger.warning("Turnstile token exceeds size limit", token_size: byte_size(token))
      {:error, :invalid_token}
    else
      case secret_key() do
        key when is_binary(key) and byte_size(key) > 0 ->
          verify_with_secret(token, key, opts)

        _invalid ->
          Logger.error("Turnstile verification failed: missing or invalid secret key")
          {:error, :turnstile_configuration_error}
      end
    end
  end

  @spec verify(any(), any()) :: {:error, :invalid_token}
  def verify(_invalid_token, _opts), do: {:error, :invalid_token}

  defp verify_with_secret(token, secret_key, opts) do
    expected_action = Keyword.get(opts, :expected_action, nil)
    expected_hostnames = Keyword.get(opts, :expected_hostnames, [])
    remote_ip = Keyword.get(opts, :remote_ip, nil)

    body =
      %{
        "secret" => secret_key,
        "response" => token
      }
      |> maybe_put_remote_ip(remote_ip)
      |> URI.encode_query()

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case Config.http_client_module().post(@verify_url, body, headers,
           receive_timeout: 5000,
           connect_options: [timeout: 5000]
         ) do
      {:ok, %Req.Response{status: 200, body: response_body}} ->
        handle_verification_response(response_body, expected_action, expected_hostnames)

      {:ok, %Req.Response{status: status_code}} ->
        Logger.error("Turnstile verification failed with unexpected status",
          status_code: status_code
        )

        {:error, :turnstile_request_failed}

      {:error, exception} ->
        Logger.error("Turnstile verification request error", error: inspect(exception))
        {:error, :turnstile_network_error}
    end
  end

  defp handle_verification_response(response_body, expected_action, expected_hostnames) do
    case Jason.decode(response_body) do
      {:ok, %{"success" => true} = decoded} ->
        action = Map.get(decoded, "action")
        hostname = Map.get(decoded, "hostname")

        with :ok <- validate_expected_action(action, expected_action),
             :ok <- validate_expected_hostname(hostname, expected_hostnames) do
          {:ok, %{action: action, hostname: hostname}}
        else
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{"success" => false, "error-codes" => error_codes}} ->
        Logger.error("Turnstile verification failed with errors",
          error_codes: inspect(error_codes)
        )

        {:error, :turnstile_verification_failed}

      {:ok, response} ->
        Logger.error("Unexpected Turnstile response format", response: inspect(response))
        {:error, :turnstile_invalid_response}

      {:error, reason} ->
        Logger.error("Failed to parse Turnstile response", reason: inspect(reason))
        {:error, :turnstile_parse_error}
    end
  end

  defp secret_key do
    System.get_env("TURNSTILE_SECRET_KEY")
  end

  @spec maybe_put_remote_ip(%{String.t() => term()}, term()) :: %{String.t() => term()}
  defdelegate maybe_put_remote_ip(params, remote_ip), to: RemoteIpParam, as: :maybe_put

  @spec validate_expected_action(any(), nil) :: :ok
  def validate_expected_action(_action, nil), do: :ok

  @spec validate_expected_action(any(), binary()) :: :ok | {:error, atom()}
  # Log when the action field is missing but one was expected. Must precede the
  # general binary clause below — its unbound first arg would otherwise swallow nil.
  def validate_expected_action(nil, expected_action) when is_binary(expected_action) do
    Logger.warning("Turnstile response missing action field",
      expected_action: expected_action,
      hint: "Cloudflare may have omitted this field; verify your Turnstile configuration"
    )

    {:error, :turnstile_missing_action}
  end

  def validate_expected_action(action, expected_action) when is_binary(expected_action) do
    if action == expected_action do
      :ok
    else
      Logger.warning("Turnstile action mismatch",
        expected_action: expected_action,
        action: action
      )

      {:error, :turnstile_action_mismatch}
    end
  end

  @spec validate_expected_hostname(any(), list()) :: :ok | {:error, atom()}
  def validate_expected_hostname(_hostname, []), do: :ok

  @spec validate_expected_hostname(nil, list()) :: {:error, atom()}
  # Log when the hostname field is missing but one was expected. Must precede the
  # general list clause below — its unbound first arg would otherwise swallow nil.
  def validate_expected_hostname(nil, [_head | _tail] = expected_hostnames) do
    Logger.warning("Turnstile response missing hostname field",
      expected_hostnames: expected_hostnames,
      hint: "Cloudflare may have omitted this field; verify your Turnstile configuration"
    )

    {:error, :turnstile_missing_hostname}
  end

  @spec validate_expected_hostname(any(), list()) :: :ok | {:error, atom()}
  def validate_expected_hostname(hostname, expected_hostnames)
      when is_list(expected_hostnames) do
    if hostname in expected_hostnames do
      :ok
    else
      Logger.warning("Turnstile hostname mismatch",
        expected_hostnames: expected_hostnames,
        hostname: hostname
      )

      {:error, :turnstile_hostname_mismatch}
    end
  end
end
