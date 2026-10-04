defmodule TymeslotWeb.Dashboard.CalendarGrid.QuickAddTest do
  @moduledoc """
  LiveView coverage for the calendar "Quick add" button. The button opens the
  create-event modal directly — there is no inline text to type — so the
  user-level action is "click Quick add, get a blank ready-to-fill draft".
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :calendar
  @moduletag :live

  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Plug.Test

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")
    insert(:calendar_integration, user: user, is_active: true)
    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user}
  end

  describe "quick-add button" do
    test "renders a button (not a text input) in the toolbar", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/calendar")

      assert has_element?(
               lv,
               "#calendar-grid-header button[phx-click='show_create_form']",
               "Quick add"
             )

      # The old inline natural-language input is gone.
      refute has_element?(lv, "#calendar-quick-add-input")
    end

    test "clicking it opens the empty create modal", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/calendar")

      html =
        lv
        |> element("#calendar-grid-header button[phx-click='show_create_form']", "Quick add")
        |> render_click()

      assert html =~ ~s(id="create-event-modal")
      assert html =~ "Event title"
      # A blank draft — no pre-filled title.
      refute html =~ ~s(value="Lunch")
    end
  end

  describe "repeat end condition" do
    defp open_repeating_draft(conn) do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/calendar")

      lv
      |> element("#calendar-grid-header button[phx-click='show_create_form']", "Quick add")
      |> render_click()

      lv
      |> form("#recurrence-editor-form-update_create_recurrence", %{"freq" => "weekly"})
      |> render_change()

      lv
    end

    test "picking “After” keeps the choice and shows the number of occurrences", %{conn: conn} do
      lv = open_repeating_draft(conn)

      lv
      |> form("#recurrence-editor-form-update_create_recurrence", %{"end_type" => "count"})
      |> render_change()

      assert has_element?(lv, ~s|select[name="end_type"] option[value="count"][selected]|)
      assert has_element?(lv, ~s|input[name="count"][value="10"]|)
    end

    test "picking “On date” keeps the choice and shows the end date", %{conn: conn} do
      lv = open_repeating_draft(conn)

      lv
      |> form("#recurrence-editor-form-update_create_recurrence", %{"end_type" => "until"})
      |> render_change()

      assert has_element?(lv, ~s|select[name="end_type"] option[value="until"][selected]|)
      assert has_element?(lv, ~s|input[type="date"][name="until"]|)
    end
  end
end
