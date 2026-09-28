defmodule Tymeslot.CustomFields.SnapshotTest do
  use Tymeslot.DataCase, async: true

  @moduletag :custom_fields

  alias Tymeslot.CustomFields.{FieldDefinition, FieldOption, Snapshot}

  test "from_meeting_type/1 returns the definitions as plain maps" do
    mt = %{
      custom_fields: [
        %FieldDefinition{
          id: "a",
          type: "short_text",
          label: "Company",
          required: true,
          options: [],
          position: 0
        }
      ]
    }

    [out] = Snapshot.from_meeting_type(mt)
    assert out["id"] == "a"
    assert out["type"] == "short_text"
    assert out["label"] == "Company"
    assert out["required"] == true
    assert out["options"] == []
    assert out["position"] == 0
  end

  test "from_meeting_type/1 serialises embedded options" do
    mt = %{
      custom_fields: [
        %FieldDefinition{
          id: "f1",
          type: "single_select",
          label: "Pick",
          required: true,
          options: [%FieldOption{key: "r", label: "Red"}],
          position: 0
        }
      ]
    }

    [out] = Snapshot.from_meeting_type(mt)
    assert out["options"] == [%{"key" => "r", "label" => "Red"}]
  end

  test "from_meeting_type/1 sorts by position" do
    mt = %{
      custom_fields: [
        %FieldDefinition{id: "b", type: "short_text", label: "B", position: 2},
        %FieldDefinition{id: "a", type: "short_text", label: "A", position: 1}
      ]
    }

    [first, second] = Snapshot.from_meeting_type(mt)
    assert first["id"] == "a"
    assert second["id"] == "b"
  end

  test "from_meeting_type/1 with no custom_fields returns []" do
    assert Snapshot.from_meeting_type(%{}) == []
    assert Snapshot.from_meeting_type(%{custom_fields: nil}) == []
  end

  test "from_definitions/1 is a no-op for plain maps" do
    plain = [%{"id" => "x", "type" => "short_text", "label" => "X"}]
    assert Snapshot.from_definitions(plain) == plain
  end

  test "from_definitions/1 sorts atom-keyed plain maps by position" do
    defs = [
      %{id: "b", type: "short_text", label: "B", position: 2},
      %{id: "a", type: "short_text", label: "A", position: 1}
    ]

    [first, _second] = Snapshot.from_definitions(defs)
    assert first["id"] == "a"
  end

  describe "per-locale translations" do
    test "resolves label/help_text/body against the given locale" do
      mt = %{
        custom_fields: [
          %FieldDefinition{
            id: "a",
            type: "note",
            label: "Company",
            help_text: "Enter your company",
            body: "Please read this",
            position: 0,
            translations: [
              %{
                locale: "de",
                label: "Firma",
                help_text: "Geben Sie Ihre Firma ein",
                body: "Bitte lesen Sie dies"
              }
            ]
          }
        ]
      }

      [out] = Snapshot.from_meeting_type(mt, "de")
      assert out["label"] == "Firma"
      assert out["help_text"] == "Geben Sie Ihre Firma ein"
      assert out["body"] == "Bitte lesen Sie dies"
    end

    test "falls back to the base value when no translation matches the locale" do
      mt = %{
        custom_fields: [
          %FieldDefinition{
            id: "a",
            type: "short_text",
            label: "Company",
            position: 0,
            translations: [%{locale: "de", label: "Firma"}]
          }
        ]
      }

      [out] = Snapshot.from_meeting_type(mt, "fr")
      assert out["label"] == "Company"
    end

    test "falls back to the base locale when no locale argument is given" do
      mt = %{
        custom_fields: [
          %FieldDefinition{
            id: "a",
            type: "short_text",
            label: "Company",
            position: 0,
            translations: [%{locale: "de", label: "Firma"}]
          }
        ]
      }

      [out] = Snapshot.from_meeting_type(mt)
      assert out["label"] == "Company"
    end
  end

  describe "per-locale option labels" do
    setup do
      mt = %{
        custom_fields: [
          %FieldDefinition{
            id: "a",
            type: "single_select",
            label: "Size",
            position: 0,
            options: [
              %FieldOption{
                key: "small",
                label: "Small",
                translations: [%{locale: "de", label: "Klein"}]
              },
              %FieldOption{key: "large", label: "Large", translations: []}
            ]
          }
        ]
      }

      {:ok, mt: mt}
    end

    test "resolves each option's label against the locale, keeping its key", %{mt: mt} do
      [out] = Snapshot.from_meeting_type(mt, "de")

      assert out["options"] == [
               %{"key" => "small", "label" => "Klein"},
               %{"key" => "large", "label" => "Large"}
             ]
    end

    test "falls back to the base label for a locale without a translation", %{mt: mt} do
      [out] = Snapshot.from_meeting_type(mt, "fr")
      assert Enum.map(out["options"], & &1["label"]) == ["Small", "Large"]
    end
  end

  test "from_definitions/1 strips nil-valued keys" do
    mt = %{
      custom_fields: [
        %FieldDefinition{
          id: "a",
          type: "short_text",
          label: "X",
          help_text: nil,
          body: nil,
          min: nil,
          max: nil
        }
      ]
    }

    [out] = Snapshot.from_meeting_type(mt)
    refute Map.has_key?(out, "help_text")
    refute Map.has_key?(out, "body")
    refute Map.has_key?(out, "min")
    refute Map.has_key?(out, "max")
  end
end
