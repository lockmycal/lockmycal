defmodule TymeslotWeb.Dashboard.BookingsManagementCancelledMeetingsTest do
  @moduledoc """
  Covers the cancelled-meetings-specific parts of the bookings management
  page: the cancellation date shown on a cancelled meeting's card, and the
  manual "Delete" button that hard-deletes it.

  Split out of `BookingsManagementTest` purely to keep that module under the
  dashboard page-size guideline.
  """

  use TymeslotWeb.LiveCase, async: true
  @moduletag :meetings
  @moduletag :live

  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers

  alias Plug.Test
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    profile = insert(:profile, user: user)

    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user, profile: profile}
  end

  describe "cancellation date" do
    test "shows the cancellation date on a cancelled meeting's card", %{conn: conn, user: user} do
      insert(:meeting,
        organizer_user_id: user.id,
        organizer_email: user.email,
        attendee_name: "Cancelled Meeting",
        status: "cancelled",
        cancelled_at: DateTime.utc_now()
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")

      view |> element("button", "Cancelled") |> render_click()
      assert render(view) =~ "Cancelled On"
    end

    test "does not show a cancellation date on an upcoming meeting's card", %{
      conn: conn,
      user: user
    } do
      insert(:meeting,
        organizer_user: user,
        organizer_email: user.email,
        attendee_name: "Upcoming Meeting"
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")

      refute render(view) =~ "Cancelled On"
    end
  end

  describe "manual delete" do
    test "shows a Delete button on a cancelled meeting's card", %{conn: conn, user: user} do
      insert(:meeting,
        organizer_user_id: user.id,
        organizer_email: user.email,
        attendee_name: "Cancelled Meeting",
        status: "cancelled",
        cancelled_at: DateTime.utc_now()
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")

      view |> element("button", "Cancelled") |> render_click()
      assert render(view) =~ "Delete"
    end

    test "does not show a Delete button on an upcoming meeting's card", %{
      conn: conn,
      user: user
    } do
      insert(:meeting,
        organizer_user: user,
        organizer_email: user.email,
        attendee_name: "Upcoming Meeting"
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")

      # The always-in-the-DOM (hidden) delete modal's own form/container ids
      # also start with "delete-meeting-", so scope to an actual button.
      refute has_element?(view, "button[id^='delete-meeting-']")
    end

    test "clicking Delete opens a confirmation modal", %{conn: conn, user: user} do
      meeting =
        insert(:meeting,
          organizer_user_id: user.id,
          organizer_email: user.email,
          attendee_name: "To Delete",
          status: "cancelled",
          cancelled_at: DateTime.utc_now()
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
      view |> element("button", "Cancelled") |> render_click()

      view |> element("#delete-meeting-#{meeting.id}") |> render_click()

      assert render(view) =~ "Permanently delete"
      assert render(view) =~ "This action cannot be undone"

      # The meeting is untouched until the modal is confirmed.
      assert Repo.get(MeetingSchema, meeting.id)
    end

    test "confirming the modal permanently deletes the meeting", %{conn: conn, user: user} do
      meeting =
        insert(:meeting,
          organizer_user_id: user.id,
          organizer_email: user.email,
          attendee_name: "To Delete",
          status: "cancelled",
          cancelled_at: DateTime.utc_now()
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
      view |> element("button", "Cancelled") |> render_click()

      view |> element("#delete-meeting-#{meeting.id}") |> render_click()
      view |> form("#delete-meeting-form") |> render_submit()

      assert render(view) =~ "Meeting deleted"
      refute render(view) =~ "To Delete"
      refute Repo.get(MeetingSchema, meeting.id)
    end

    test "dismissing the modal without confirming keeps the meeting", %{conn: conn, user: user} do
      meeting =
        insert(:meeting,
          organizer_user_id: user.id,
          organizer_email: user.email,
          attendee_name: "Kept Meeting",
          status: "cancelled",
          cancelled_at: DateTime.utc_now()
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
      view |> element("button", "Cancelled") |> render_click()

      view |> element("#delete-meeting-#{meeting.id}") |> render_click()
      view |> element("button[phx-click*='hide_delete_modal']", "Keep") |> render_click()

      assert render(view) =~ "Kept Meeting"
      assert Repo.get(MeetingSchema, meeting.id)
    end

    test "cannot delete a non-cancelled meeting by forging the show_delete_modal event", %{
      conn: conn,
      user: user
    } do
      meeting =
        insert(:meeting,
          organizer_user: user,
          organizer_email: user.email,
          attendee_name: "Still Upcoming"
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")

      view
      |> with_target("#bookings-management")
      |> render_click("show_delete_modal", %{"id" => meeting.id})

      refute render(view) =~ "Permanently delete"
      assert Repo.get(MeetingSchema, meeting.id)
    end
  end
end
