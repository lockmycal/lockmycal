defmodule TymeslotWeb.Dashboard.BookingsManagement.QuickAddContactPickerTest do
  @moduledoc """
  Covers the "pick from contacts" shortcut on the Meetings page's own
  "Quick add" dialog — mirrors
  `TymeslotWeb.Dashboard.CalendarGrid.ContactPickerTest`, since
  `query_contacts/2` and `close_contact_picker/2` now delegate to the same
  `TymeslotWeb.Dashboard.Shared.ContactPickerHandlers.query/3` and `.close/1`
  the calendar's own dialog uses, instead of duplicating that logic.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :meetings
  @moduletag :live

  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Plug.Test

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")
    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user}
  end

  defp open_quick_add(lv) do
    lv |> element("button[phx-click='show_create_form']", "Add meeting") |> render_click()
  end

  describe "guest contact picker" do
    test "typing filters and shows matching contacts", %{conn: conn, user: user} do
      contact =
        insert(:contact, organizer_user: user, name: "Ada Lovelace", email: "ada@example.com")

      insert(:contact, organizer_user: user, name: "Grace Hopper", email: "grace@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      html =
        lv
        |> with_target("#bookings-management")
        |> render_hook("guest_contact_query", %{"query" => "ada"})

      assert html =~ contact.name
      refute html =~ "Grace Hopper"
    end

    test "only matches the current organizer's own contacts", %{conn: conn} do
      other_user = insert(:user)
      insert(:contact, organizer_user: other_user, name: "Not Mine", email: "notmine@ex.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      html =
        lv
        |> with_target("#bookings-management")
        |> render_hook("guest_contact_query", %{"query" => "not"})

      refute html =~ "Not Mine"
    end

    test "closing the picker hides the dropdown", %{conn: conn, user: user} do
      insert(:contact, organizer_user: user, name: "Ada Lovelace", email: "ada@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      lv
      |> with_target("#bookings-management")
      |> render_hook("guest_contact_query", %{"query" => "ada"})

      html =
        lv
        |> with_target("#bookings-management")
        |> render_hook("close_guest_contact_picker", %{})

      refute html =~ "Ada Lovelace</span>"
    end
  end
end
