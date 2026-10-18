defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.TypeTranslationsTest do
  use ExUnit.Case, async: true

  @moduletag :meeting_types

  alias Tymeslot.MeetingTypes.MeetingTypeTranslation
  alias TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.TypeTranslations

  describe "upsert/3" do
    test "adds a row for a locale that has none, blanks stored as nil" do
      assert [%MeetingTypeTranslation{locale: "de", name: "Kurzes Gespräch", description: nil}] =
               TypeTranslations.upsert([], "de", %{"name" => "Kurzes Gespräch"})
    end

    test "updates only the field that changed and leaves the other as it was" do
      existing = [
        %MeetingTypeTranslation{id: "t1", locale: "de", name: "Alt", description: "Bleibt"}
      ]

      assert [%MeetingTypeTranslation{id: "t1", name: "Neu", description: "Bleibt"}] =
               TypeTranslations.upsert(existing, "de", %{"name" => "Neu"})
    end

    test "clearing a field stores nil and keeps other locales untouched" do
      existing = [
        %MeetingTypeTranslation{id: "t1", locale: "de", name: "Name", description: "Text"},
        %MeetingTypeTranslation{id: "t2", locale: "fr", name: "Nom", description: nil}
      ]

      assert [%{locale: "de", description: nil}, %{locale: "fr", name: "Nom"}] =
               TypeTranslations.upsert(existing, "de", %{"description" => ""})
    end
  end
end
