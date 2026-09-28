defmodule Tymeslot.Utils.UriUtils do
  @moduledoc """
  Utility functions for URI comparison and decoding.
  """

  @doc """
  Decodes a percent-encoded URI string. Returns the original string unchanged
  if the input contains malformed percent-sequences (e.g. `%GG`).
  """
  @spec safe_decode(String.t()) :: String.t()
  def safe_decode(str) do
    URI.decode(str)
  end

  @doc """
  Compares two URI strings for equality, treating percent-encoded and decoded
  forms as equivalent (per RFC 3986). Returns `false` if either argument is nil.
  """
  @spec uri_safe_match?(String.t() | nil, String.t() | nil) :: boolean()
  def uri_safe_match?(a, b) when is_binary(a) and is_binary(b) do
    a == b || safe_decode(a) == safe_decode(b)
  end

  def uri_safe_match?(_a, _b), do: false

  @doc """
  Returns a URL's origin (`scheme://host`), appending the port only when it
  isn't the scheme's default — a bare `scheme://host` is otherwise assumed by
  consumers like CSP host-sources to mean the default port only. Returns
  `nil` for a relative URL or one with an unrecognized scheme.
  """
  @spec origin(String.t()) :: String.t() | nil
  def origin(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host, port: port}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        default_port = if scheme == "https", do: 443, else: 80

        if port && port != default_port do
          "#{scheme}://#{host}:#{port}"
        else
          "#{scheme}://#{host}"
        end

      _uri ->
        nil
    end
  end
end
