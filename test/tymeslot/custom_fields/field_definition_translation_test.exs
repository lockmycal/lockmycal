defmodule Tymeslot.CustomFields.FieldDefinitionTranslationTest do
  use ExUnit.Case, async: true

  @moduletag :custom_fields
  @moduletag :schema

  import Tymeslot.DataCase, only: [errors_on: 1]

  alias Ecto.Changeset
  alias Tymeslot.CustomFields.FieldDefinitionTranslation

  describe "changeset/2" do
    test "requires a locale" do
      cs = FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{"label" => "Hi"})

      refute cs.valid?
      assert "can't be blank" in errors_on(cs).locale
    end

    test "a row may translate just one field" do
      cs =
        FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{
          "locale" => "de",
          "label" => "Firma"
        })

      assert cs.valid?
    end

    test "rejects an unsupported locale code" do
      cs =
        FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{"locale" => "xx"})

      refute cs.valid?
      assert "is invalid" in errors_on(cs).locale
    end

    test "rejects the dev-only pseudo locale" do
      cs =
        FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{
          "locale" => "pseudo"
        })

      refute cs.valid?
      assert "is invalid" in errors_on(cs).locale
    end

    test "auto-fills id when absent" do
      cs =
        FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{"locale" => "de"})

      assert cs |> Changeset.get_field(:id) |> byte_size() > 0
    end

    test "a blank field is normalised to nil, not an empty string" do
      cs =
        FieldDefinitionTranslation.changeset(
          %FieldDefinitionTranslation{label: "Old"},
          %{"locale" => "de", "label" => ""}
        )

      assert Changeset.get_field(cs, :label) == nil
    end

    test "rejects a label over the shared length cap" do
      cs =
        FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{
          "locale" => "de",
          "label" => String.duplicate("a", 121)
        })

      refute cs.valid?
      assert "should be at most 120 character(s)" in errors_on(cs).label
    end

    test "rejects a help_text over the shared length cap" do
      cs =
        FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{
          "locale" => "de",
          "help_text" => String.duplicate("a", 301)
        })

      refute cs.valid?
      assert "should be at most 300 character(s)" in errors_on(cs).help_text
    end

    test "body has no length cap, matching the base field" do
      cs =
        FieldDefinitionTranslation.changeset(%FieldDefinitionTranslation{}, %{
          "locale" => "de",
          "body" => String.duplicate("a", 5000)
        })

      assert cs.valid?
    end
  end
end
