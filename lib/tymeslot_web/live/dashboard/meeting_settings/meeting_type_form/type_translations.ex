defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.TypeTranslations do
  @moduledoc """
  The meeting type's own per-locale name and description, as edited on the
  Details tab's locale tabs: folds one locale's input into the form's
  in-memory translations list. Question translations have their own module,
  `QuestionTranslations`.
  """

  alias Ecto.UUID
  alias Tymeslot.MeetingTypes.MeetingTypeTranslation

  @doc """
  Upserts one locale's row into the in-memory translations list, matching
  `custom_questions_section.ex`'s idiom for a new `%FieldDefinition{}`: build
  the struct directly, id included, since full changeset validation only
  happens once at persist time (`MeetingTypeTranslation.changeset/2`).

  `params` carries only the one field that actually changed — each
  translation input fires its own `phx-change`, same as the base
  `meeting_type[name]`/`[description]` inputs — so an existing row is
  updated one field at a time; the field absent from `params` must be left
  exactly as it was, not reset to blank.
  """
  @spec upsert([MeetingTypeTranslation.t()], String.t(), map()) :: [MeetingTypeTranslation.t()]
  def upsert(translations, locale, params) do
    case Enum.find_index(translations, &(&1.locale == locale)) do
      nil ->
        new_row = %MeetingTypeTranslation{
          id: UUID.generate(),
          locale: locale,
          name: blank_to_nil(Map.get(params, "name", "")),
          description: blank_to_nil(Map.get(params, "description", ""))
        }

        translations ++ [new_row]

      index ->
        List.update_at(translations, index, &put_translation_fields(&1, params))
    end
  end

  defp put_translation_fields(row, params) do
    row
    |> maybe_put_translation_field(:name, params["name"])
    |> maybe_put_translation_field(:description, params["description"])
  end

  defp maybe_put_translation_field(row, _field, nil), do: row

  defp maybe_put_translation_field(row, field, value),
    do: Map.put(row, field, blank_to_nil(value))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
