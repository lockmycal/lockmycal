defmodule Tymeslot.CustomFields.Snapshot do
  @moduledoc """
  Builds an immutable, plain-map snapshot of a meeting type's custom
  field definitions to persist on a booking. The snapshot is what the
  booker actually saw at the time of submission.

  Always plain string-keyed maps — never embedded schema structs — so
  that read-time consumers (LiveView, emails, ICS) never depend on
  Ecto runtime semantics.
  """

  alias Tymeslot.CustomFields.FieldDefinition
  alias Tymeslot.I18n.Resolve
  alias Tymeslot.Locales

  @doc """
  Builds a snapshot from a meeting type struct or map, resolving each
  definition's `label`/`help_text`/`body` against `locale` first (see
  `Tymeslot.CustomFields.FieldDefinitionTranslation`). Defaults to the
  instance's booking locale so existing callers (and tests) that predate
  translations keep working unchanged.
  """
  @spec from_meeting_type(map(), String.t()) :: [map()]
  def from_meeting_type(meeting_type, locale \\ Locales.booking_default_locale())

  def from_meeting_type(%{custom_fields: defs}, locale) when is_list(defs),
    do: from_definitions(defs, locale)

  def from_meeting_type(_meeting_type, _locale), do: []

  @doc "Normalises a list of definitions (struct or map) to a list of plain maps."
  @spec from_definitions([FieldDefinition.t() | map()], String.t()) :: [map()]
  def from_definitions(defs, locale \\ Locales.booking_default_locale()) do
    defs
    |> Enum.sort_by(&position/1)
    |> Enum.map(&to_plain_map(&1, locale))
  end

  defp position(%FieldDefinition{position: p}), do: p || 0
  defp position(%{"position" => p}), do: p || 0
  defp position(%{position: p}), do: p || 0
  defp position(_field), do: 0

  defp to_plain_map(%FieldDefinition{} = d, locale) do
    raw = %{
      "id" => d.id,
      "type" => d.type,
      "label" => Resolve.text(d.translations, locale, :label, d.label),
      "help_text" => Resolve.text(d.translations, locale, :help_text, d.help_text),
      "required" => d.required,
      "position" => d.position,
      "options" => Enum.map(d.options || [], &option_to_plain_map(&1, locale)),
      "body" => Resolve.text(d.translations, locale, :body, d.body),
      "min" => d.min,
      "max" => d.max
    }

    drop_nils(raw)
  end

  defp to_plain_map(map, _locale) when is_map(map) do
    stringified = Enum.into(map, %{}, fn {k, v} -> {to_string(k), v} end)
    drop_nils(stringified)
  end

  defp option_to_plain_map(option, locale) do
    %{
      "key" => option.key,
      "label" => Resolve.text(option.translations, locale, :label, option.label)
    }
  end

  defp drop_nils(map), do: Map.reject(map, fn {_k, v} -> is_nil(v) end)
end
