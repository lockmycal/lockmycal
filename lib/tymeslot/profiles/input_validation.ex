defmodule Tymeslot.Profiles.InputValidation do
  @moduledoc """
  Sanitisation for the profile's free-form text bound for the booking page: the
  booking text (heading, greeting, instruction) and the organiser's
  introduction (headline, bio).

  Both are organiser-authored prose rendered on a public page, so they go
  through the same `:plain_text` sanitiser as meeting type names and
  descriptions: encoding integrity, null-byte removal, byte caps and security
  logging, without the HTML and SQL stripping that would mangle legitimate
  punctuation. An apostrophe in "Let's talk" and an arrow in "You -> me" have
  to survive, and they do because Phoenix escapes on render and Ecto
  parameterises on write, which is precisely what makes `:plain_text` the
  right profile rather than a weaker one. It keeps line breaks, which the bio
  relies on.

  Length is deliberately *not* enforced here. The caps are user-facing rules
  with translated changeset errors, so `ProfileSchema.booking_text_changeset/2`
  and `ProfileSchema.intro_changeset/2` own them; this module handles only what
  a changeset cannot see.

  Each row of `booking_text_translations` (see
  `Tymeslot.Profiles.ProfileBookingTextTranslation`) carries the same three
  organiser-authored strings for one locale, so it goes through the identical
  sanitiser — a translation reaches the same public page as the base text and
  deserves the same treatment, not a weaker one just because it is nested.
  """

  alias Tymeslot.Security.UniversalSanitizer

  @booking_text_fields ~w(booking_heading booking_greeting booking_instruction)
  @intro_fields ~w(headline bio)

  @typedoc "String-keyed params, as submitted by a dashboard form."
  @type params :: %{optional(String.t()) => term()}

  @type result :: {:ok, params()} | {:error, %{atom() => String.t()}}

  @doc """
  Sanitises the three booking text fields in `params` and, when present, each
  row of `params["booking_text_translations"]`, leaving every other key
  untouched.

  Returns the params with sanitised values, or the first field that failed with
  a message suitable for an inline form error.
  """
  @spec validate_booking_text(params(), keyword()) :: result()
  def validate_booking_text(params, opts \\ []) when is_map(params),
    do: validate_fields(params, @booking_text_fields, opts)

  @doc """
  Sanitises the headline and bio in `params`, leaving every other key
  untouched. Returns what `validate_booking_text/2` returns.
  """
  @spec validate_intro(params(), keyword()) :: result()
  def validate_intro(params, opts \\ []) when is_map(params),
    do: validate_fields(params, @intro_fields, opts)

  defp validate_fields(params, fields, opts) do
    metadata = Keyword.get(opts, :metadata, %{})

    with {:ok, params} <- sanitize_fields(params, fields, metadata) do
      sanitize_translations(params, metadata)
    end
  end

  defp sanitize_fields(map, fields, metadata) do
    Enum.reduce_while(fields, {:ok, map}, fn field, {:ok, acc} ->
      case sanitize_field(Map.get(acc, field), field, metadata) do
        {:ok, :absent} -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, field, value)}}
        {:error, reason} -> {:halt, {:error, %{String.to_existing_atom(field) => reason}}}
      end
    end)
  end

  defp sanitize_translations(%{"booking_text_translations" => rows} = params, metadata)
       when is_list(rows) do
    case sanitize_translation_rows(rows, metadata) do
      {:ok, sanitized_rows} -> {:ok, Map.put(params, "booking_text_translations", sanitized_rows)}
      error -> error
    end
  end

  defp sanitize_translations(params, _metadata), do: {:ok, params}

  defp sanitize_translation_rows(rows, metadata) do
    result =
      Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, acc} ->
        case sanitize_fields(row, @booking_text_fields, metadata) do
          {:ok, sanitized} -> {:cont, {:ok, [sanitized | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, sanitized} -> {:ok, Enum.reverse(sanitized)}
      error -> error
    end
  end

  # A field the form did not submit is not an error: the dashboard omits the
  # booking text fields whenever that customisation is switched off.
  defp sanitize_field(nil, _field, _metadata), do: {:ok, :absent}

  defp sanitize_field(value, field, metadata) when is_binary(value) do
    UniversalSanitizer.sanitize_and_validate(value,
      mode: :plain_text,
      field: String.to_existing_atom(field),
      metadata: metadata
    )
  end

  # Anything that is not a string never reached the form legitimately.
  defp sanitize_field(_value, _field, _metadata), do: {:error, "must be text"}
end
