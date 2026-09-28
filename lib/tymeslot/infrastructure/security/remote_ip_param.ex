defmodule Tymeslot.Infrastructure.Security.RemoteIpParam do
  @moduledoc """
  Shared `remoteip` request-param handling for bot-protection siteverify
  calls (`Tymeslot.Infrastructure.Security.Recaptcha` and `...Turnstile`).
  Neither Google's nor Cloudflare's API cares which provider is asking, so
  this validation lives in one place rather than duplicated per provider.
  """

  require Logger

  @doc """
  Adds a `"remoteip"` entry to `params` when `remote_ip` is a plausible,
  non-blank, non-"unknown" IPv4/IPv6 address — otherwise returns `params`
  unchanged.
  """
  @spec maybe_put(%{String.t() => term()}, binary()) :: %{String.t() => term()}
  def maybe_put(params, remote_ip) when is_binary(remote_ip) do
    # Reject extremely long strings to prevent memory pressure during validation
    if byte_size(remote_ip) > 100 do
      params
    else
      trimmed = String.trim(remote_ip)

      cond do
        trimmed == "" ->
          params

        trimmed == "unknown" ->
          # Don't send "unknown" to the provider's API
          params

        valid_ip?(trimmed) ->
          Map.put(params, "remoteip", trimmed)

        true ->
          # Invalid IP format - don't send it
          params
      end
    end
  end

  @spec maybe_put(%{String.t() => term()}, any()) :: %{String.t() => term()}
  def maybe_put(params, _other), do: params

  # Validates that a string is a valid IPv4 or IPv6 address.
  # Rejects IPv6 addresses with scope IDs (e.g., "fe80::1%eth0") as they
  # should not be sent to external APIs and are link-local only.
  defp valid_ip?(ip_string) when is_binary(ip_string) do
    trimmed = String.trim(ip_string)

    # Reject IPv6 with scope IDs (contains %)
    if String.contains?(trimmed, "%") do
      false
    else
      case :inet.parse_address(String.to_charlist(trimmed)) do
        {:ok, _parsed_ip} -> true
        {:error, _parse_error} -> false
      end
    end
  rescue
    e in ArgumentError ->
      # Handle string encoding errors (rare but possible with malformed input)
      Logger.debug("Failed to validate IP address",
        ip: inspect(ip_string),
        error: inspect(e)
      )

      false
  end
end
