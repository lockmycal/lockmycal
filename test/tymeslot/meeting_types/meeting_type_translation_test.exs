defmodule Tymeslot.MeetingTypes.MeetingTypeTranslationTest do
  use Tymeslot.DataCase, async: true

  @moduletag :meeting_types
  @moduletag :schema

  alias Ecto.Changeset
  alias Tymeslot.MeetingTypes.MeetingTypeTranslation

  describe "changeset/2" do
    test "requires a locale" do
      cs = MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{"name" => "Hallo"})

      refute cs.valid?
      assert "can't be blank" in errors_on(cs).locale
    end

    test "accepts a supported locale with both fields set" do
      attrs = %{"locale" => "de", "name" => "Kurzes Gespräch", "description" => "Kurz und knapp"}
      cs = MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, attrs)

      assert cs.valid?
    end

    test "a row may translate just one field" do
      cs =
        MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{
          "locale" => "de",
          "name" => "Kurzes Gespräch"
        })

      assert cs.valid?
    end

    test "rejects an unsupported locale code" do
      cs = MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{"locale" => "xx"})

      refute cs.valid?
      assert "is invalid" in errors_on(cs).locale
    end

    test "rejects the dev-only pseudo locale" do
      cs = MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{"locale" => "pseudo"})

      refute cs.valid?
      assert "is invalid" in errors_on(cs).locale
    end

    test "auto-fills id when absent" do
      cs = MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{"locale" => "de"})

      assert cs |> Changeset.get_field(:id) |> byte_size() > 0
    end

    test "keeps an existing id" do
      cs =
        MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{
          "id" => "existing-id",
          "locale" => "de"
        })

      assert Changeset.get_field(cs, :id) == "existing-id"
    end

    test "a blank name is normalised to nil, not an empty string" do
      cs =
        MeetingTypeTranslation.changeset(%MeetingTypeTranslation{name: "Old"}, %{
          "locale" => "de",
          "name" => ""
        })

      assert Changeset.get_field(cs, :name) == nil
    end

    test "rejects a name over the shared name length cap" do
      cs =
        MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{
          "locale" => "de",
          "name" => String.duplicate("a", 101)
        })

      refute cs.valid?
      assert "should be at most 100 character(s)" in errors_on(cs).name
    end

    test "rejects a description over the shared description length cap" do
      cs =
        MeetingTypeTranslation.changeset(%MeetingTypeTranslation{}, %{
          "locale" => "de",
          "description" => String.duplicate("a", 501)
        })

      refute cs.valid?
      assert "should be at most 500 character(s)" in errors_on(cs).description
    end
  end
end
