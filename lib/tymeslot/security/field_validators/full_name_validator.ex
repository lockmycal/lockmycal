defmodule Tymeslot.Security.FieldValidators.FullNameValidator do
  @moduledoc """
  Full name field validation for user registration.

  Validates full name with appropriate length limits while allowing
  international names and handling optional name fields.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  @name_max_length 100
  @invalid_chars_regex ~r/[<>"%;`\\\/\{\}\[\]]/

  @doc """
  Validates full name fields with specific error messages.

  Full name is optional by default (signup), so empty values are allowed; pass
  `required: true` where a name must be given (onboarding, profile settings).

  ## Examples

      iex> validate("John Smith")
      :ok
      
      iex> validate("")
      :ok
      
      iex> validate("José María")
      :ok
      
      iex> validate("John<script>")
      {:error, "Full name contains invalid characters"}
  """
  @spec validate(any(), keyword()) :: :ok | {:error, String.t()}
  def validate(full_name, opts \\ [])

  def validate(nil, opts), do: blank_result(opts)
  def validate("", opts), do: blank_result(opts)

  def validate(full_name, opts) when is_binary(full_name) do
    max_length = Keyword.get(opts, :max_length, @name_max_length)

    trimmed_name = String.trim(full_name)

    if trimmed_name == "" do
      blank_result(opts)
    else
      validate_non_empty_name(trimmed_name, max_length)
    end
  end

  def validate(_full_name, _opts) do
    {:error, "Full name must be a text value"}
  end

  # Private helper functions

  defp blank_result(opts) do
    if Keyword.get(opts, :required, false) do
      {:error, dgettext("errors", "Full name is required")}
    else
      :ok
    end
  end

  defp validate_non_empty_name(name, max_length) do
    cond do
      String.length(name) > max_length ->
        {:error, "Full name is too long (maximum #{max_length} characters)"}

      Regex.match?(@invalid_chars_regex, name) ->
        {:error, "Full name contains invalid characters"}

      all_numbers?(name) ->
        {:error, "Full name cannot be only numbers"}

      excessive_whitespace?(name) ->
        {:error, "Full name contains excessive whitespace"}

      true ->
        :ok
    end
  end

  defp all_numbers?(name) do
    Regex.match?(~r/^\d+$/, String.replace(name, " ", ""))
  end

  defp excessive_whitespace?(name) do
    # Check for more than 2 consecutive spaces
    Regex.match?(~r/\s{3,}/, name)
  end
end
