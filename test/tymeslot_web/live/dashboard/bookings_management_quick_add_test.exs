defmodule TymeslotWeb.Dashboard.BookingsManagementQuickAddTest do
  @moduledoc """
  Covers the Meetings page's own "Quick add" dialog: the primary button next
  to the "Meetings List" subheading, and the reused calendar create-event
  dialog (`TymeslotWeb.Dashboard.CalendarGrid.Modals.CreateEventModal`) it
  opens — same Event/Meeting toggle and behaviour as the calendar's own
  "Quick add", including its "pick from contacts" shortcut.
  """

  use TymeslotWeb.LiveCase, async: true
  @moduletag :meetings
  @moduletag :live

  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers

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

  defp fill_guest(lv, name, email) do
    lv |> element("#create-meeting-guest-name") |> render_blur(%{"value" => name})
    lv |> element("#create-meeting-guest-email") |> render_blur(%{"value" => email})
  end

  describe "Add meeting button" do
    test "renders next to the Meetings List subheading on every filter tab", %{conn: conn} do
      {:ok, lv, html} = live(conn, ~p"/dashboard/meetings")
      assert html =~ ~s(phx-click="show_create_form")

      for label <- ["Past", "Cancelled"] do
        html = lv |> element("button", label) |> render_click()
        assert html =~ ~s(phx-click="show_create_form")
      end
    end
  end

  describe "without a connected calendar" do
    test "opens the same dialog as the calendar's Quick add, straight in meeting mode", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")

      html = open_quick_add(lv)

      assert html =~ ~s(id="create-event-modal")
      assert html =~ "New Meeting"
      assert html =~ ~s(id="create-meeting-guest-name")
      assert html =~ ~s(id="create-meeting-guest-email")
      assert html =~ ~s(id="create-meeting-contact-picker")
      # No mode toggle: nothing to write a bare event to, same as the
      # calendar's own dialog with no calendar connected.
      refute html =~ ~s(data-testid="create-mode-meeting")
      refute html =~ ~s(value="Lunch")
    end
  end

  describe "with a connected calendar" do
    test "opens the full dialog — toggle, calendar picker — defaulting to event mode, exactly like the calendar page",
         %{conn: conn, user: user} do
      insert(:calendar_integration, user: user, is_active: true)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")

      html = open_quick_add(lv)

      assert html =~ "New Event"
      assert html =~ ~s(data-testid="create-mode-meeting")
      refute html =~ ~s(id="create-meeting-guest-name")

      html =
        lv
        |> element(~s{[data-testid="create-mode-meeting"]})
        |> render_click()

      assert html =~ "New Meeting"
      assert html =~ ~s(id="create-meeting-guest-name")
      assert html =~ ~s(id="create-meeting-contact-picker")
    end
  end

  describe "validation" do
    test "saving without guest details flashes a validation error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      lv |> element("button", "Create") |> render_click()
      # Flash.error/1 forwards to the parent LiveView via `send/2`; it lands
      # on the next render, not the one the click itself returns.
      html = render(lv)

      assert html =~ "Guest name is required"
      assert html =~ ~s(id="create-event-modal")
    end

    test "saving with an invalid email flashes an email error", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      fill_guest(lv, "Ada Lovelace", "not-an-email")

      lv |> element("button", "Create") |> render_click()
      html = render(lv)

      assert html =~ "A valid guest email is required"
    end
  end

  describe "contact picker" do
    test "typing filters and selecting a contact fills guest name and email", %{
      conn: conn,
      user: user
    } do
      contact =
        insert(:contact, organizer_user: user, name: "Ada Lovelace", email: "ada@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      html =
        lv
        |> element("#create-meeting-contact-picker-form")
        |> render_change(%{"query" => "ada"})

      assert html =~ "Ada Lovelace"

      html =
        lv
        |> element("button[phx-click='select_guest_contact']", "Ada Lovelace")
        |> render_click()

      assert html =~ ~s(value="Ada Lovelace")
      assert html =~ ~s(value="ada@example.com")
      refute html =~ contact.email <> "</span>"
    end
  end

  describe "creating a meeting" do
    test "a valid submission books the meeting and closes the modal", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      fill_guest(lv, "Ada Lovelace", "ada@example.com")

      first = lv |> element("button", "Create") |> render_click()
      refute first =~ ~s(id="create-event-modal")

      html = render(lv)
      assert html =~ "Meeting created and invitation sent"
      assert html =~ "Ada Lovelace"
    end

    test "the organiser's own address is rejected", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")
      open_quick_add(lv)

      fill_guest(lv, "Ada Lovelace", user.email)

      first = lv |> element("button", "Create") |> render_click()
      assert first =~ ~s(id="create-event-modal")

      html = render(lv)
      assert html =~ "You cannot add yourself as a guest"
    end
  end
end
