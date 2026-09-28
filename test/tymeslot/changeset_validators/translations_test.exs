defmodule Tymeslot.ChangesetValidators.TranslationsTest do
  use Tymeslot.DataCase, async: true

  @moduletag :i18n
  @moduletag :unit

  alias Tymeslot.MeetingTypes.MeetingTypeSchema

  # `validate_unique_locales/2` is exercised through the one owning schema
  # that wires it up, matching how `validate_unique_option_keys/1` (the
  # precedent this mirrors) is only ever tested via `FieldDefinition`'s own
  # changeset rather than in isolation.
  describe "validate_unique_locales/2 (via MeetingTypeSchema)" do
    test "accepts distinct locales" do
      attrs = %{
        name: "Intro call",
        duration_minutes: 30,
        user_id: 1,
        translations: [
          %{"locale" => "de", "name" => "Kurzes Gespräch"},
          %{"locale" => "fr", "name" => "Discussion rapide"}
        ]
      }

      cs = MeetingTypeSchema.changeset(%MeetingTypeSchema{}, attrs)
      refute Map.has_key?(errors_on(cs), :translations)
    end

    test "rejects two rows for the same locale" do
      attrs = %{
        name: "Intro call",
        duration_minutes: 30,
        user_id: 1,
        translations: [
          %{"locale" => "de", "name" => "Kurzes Gespräch"},
          %{"locale" => "de", "name" => "Kurzes Treffen"}
        ]
      }

      cs = MeetingTypeSchema.changeset(%MeetingTypeSchema{}, attrs)
      refute cs.valid?
      assert "must not contain duplicate locales" in errors_on(cs).translations
    end

    test "an empty translations list is valid" do
      attrs = %{name: "Intro call", duration_minutes: 30, user_id: 1, translations: []}

      cs = MeetingTypeSchema.changeset(%MeetingTypeSchema{}, attrs)
      refute Map.has_key?(errors_on(cs), :translations)
    end
  end
end
