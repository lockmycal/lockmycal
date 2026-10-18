defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeTranslationsTest do
  @moduledoc """
  The meeting type form's per-locale name/description tabs: a translation is
  saved on its own row and never touches the base fields or another locale.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :meeting_types
  @moduletag :live

  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.MeetingTypes

  setup :setup_dashboard_user

  describe "Per-locale name/description translations" do
    test "switching to a locale tab and editing name/description doesn't touch the base fields",
         %{conn: conn, user: user} do
      meeting_type =
        insert(:meeting_type, user: user, name: "Quick Chat", description: "A short call")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

      view
      |> element("[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
      |> render_click()

      view
      |> element("button[phx-click='switch_translation_locale'][phx-value-option='de']")
      |> render_click()

      view
      |> element(~s|input[name="translation[name]"]|)
      |> render_change(%{"translation" => %{"name" => "Kurzes Gespräch"}})

      updated = MeetingTypes.get_meeting_type(meeting_type.id, user.id)
      assert updated.name == "Quick Chat"
      assert updated.description == "A short call"
      assert [translation] = updated.translations
      assert translation.locale == "de"
      assert translation.name == "Kurzes Gespräch"
      assert translation.description == nil
    end

    test "editing the description after the name doesn't wipe the name (regression)",
         %{conn: conn, user: user} do
      meeting_type =
        insert(:meeting_type, user: user, name: "Quick Chat", description: "A short call")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

      view
      |> element("[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
      |> render_click()

      view
      |> element("button[phx-click='switch_translation_locale'][phx-value-option='de']")
      |> render_click()

      # Each translation input fires its own phx-change (same as the base
      # meeting_type[name]/[description] inputs), so this event carries only
      # "name" — the bug being guarded against reset "description" (and vice
      # versa) to blank whenever the sibling field wasn't the one that changed.
      view
      |> element(~s|input[name="translation[name]"]|)
      |> render_change(%{"translation" => %{"name" => "Kurzes Gespräch"}})

      view
      |> element(~s|input[name="translation[description]"]|)
      |> render_change(%{"translation" => %{"description" => "Kurzer Anruf"}})

      updated = MeetingTypes.get_meeting_type(meeting_type.id, user.id)
      assert [translation] = updated.translations
      assert translation.name == "Kurzes Gespräch"
      assert translation.description == "Kurzer Anruf"
    end

    test "editing a second locale doesn't clobber the first locale's already-saved row",
         %{conn: conn, user: user} do
      meeting_type = insert(:meeting_type, user: user, name: "Quick Chat")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

      view
      |> element("[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
      |> render_click()

      view
      |> element("button[phx-click='switch_translation_locale'][phx-value-option='de']")
      |> render_click()

      view
      |> element(~s|input[name="translation[name]"]|)
      |> render_change(%{"translation" => %{"name" => "Kurzes Gespräch"}})

      view
      |> element("button[phx-click='switch_translation_locale'][phx-value-option='fr']")
      |> render_click()

      view
      |> element(~s|input[name="translation[name]"]|)
      |> render_change(%{"translation" => %{"name" => "Discussion rapide"}})

      updated = MeetingTypes.get_meeting_type(meeting_type.id, user.id)
      translations = Map.new(updated.translations, &{&1.locale, &1.name})

      assert translations == %{"de" => "Kurzes Gespräch", "fr" => "Discussion rapide"}
      assert updated.name == "Quick Chat"
    end
  end
end
