defmodule Tymeslot.Integrations.Video.TemplateConfig do
  @template_variable "{{meeting_id}}"
  @hash_length 16

  @moduledoc """
  Centralized configuration for custom video URL template processing.

  This module defines the template syntax, hashing parameters, and sample values
  used across the custom video provider system.

  ## Template Variables

  Only `{{meeting_id}}` is supported. This variable is replaced with a secure hash
  of the actual meeting ID during room creation.

  ## Hash Configuration

  The system uses SHA256 hashing truncated to #{@hash_length} hexadecimal characters.

  ### Collision Resistance
  With #{@hash_length} hex characters (#{@hash_length * 4} bits of entropy):
  - Total possible values: #{trunc(:math.pow(16, @hash_length))} (16^#{@hash_length})
  - 50% collision probability (birthday paradox): ~#{trunc(:math.sqrt(:math.pow(16, @hash_length)))} meetings
  - 1% collision probability: ~#{trunc(:math.sqrt(:math.pow(16, @hash_length)) / 10)} meetings

  ### Security Considerations
  - Hashing prevents URL injection attacks (query params, path traversal, fragments)
  - #{@hash_length}-character hashes provide strong resistance to brute-force enumeration
  - Meeting IDs are deterministically hashed for idempotency (same ID → same URL)

  ## URL Length Limits
  - Maximum processed URL length: 255 characters (database constraint)
  - URLs exceeding this limit after template processing will be rejected
  """

  # Generate a realistic sample hash matching the production format
  @sample_hash :crypto.hash(:sha256, "sample-meeting-id-for-preview")
               |> Base.encode16(case: :lower)
               |> String.slice(0, @hash_length)

  @doc """
  Returns the template variable syntax used in URLs.

  ## Example
      iex> TemplateConfig.template_variable()
      "{{meeting_id}}"
  """
  @spec template_variable() :: String.t()
  def template_variable, do: @template_variable

  @doc """
  Returns the hash length in hexadecimal characters.

  ## Example
      iex> TemplateConfig.hash_length()
      16
  """
  @spec hash_length() :: pos_integer()
  def hash_length, do: @hash_length

  @doc """
  Returns a sample hash for preview/testing purposes.

  The sample hash is a #{@hash_length}-character lowercase hexadecimal string
  matching the format of production hashes.

  ## Example
      iex> TemplateConfig.sample_hash()
      "a1b2c3d4e5f67890"  # Actual value will vary
  """
  @spec sample_hash() :: String.t()
  def sample_hash, do: @sample_hash

  @doc """
  Maximum allowed length for processed URLs (in characters).

  This matches the database VARCHAR constraint for the meeting_url field.
  """
  @spec max_url_length() :: pos_integer()
  def max_url_length, do: 255
end
