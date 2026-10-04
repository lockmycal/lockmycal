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
  alias Tymeslot.Profiles
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

    test "does not show a Delete button on a cancelled meeting the user only attended", %{
      conn: conn,
      user: user
    } do
      # Listed because the user is its attendee, but only the organiser may
      # delete it — a button here could only ever fail.
      organizer = insert(:user)

      meeting =
        insert(:meeting,
          organizer_user_id: organizer.id,
          organizer_email: organizer.email,
          # The card of a meeting the user attends is named after its host.
          organizer_name: "Someone Else's Meeting",
          attendee_email: user.email,
          status: "cancelled",
          cancelled_at: DateTime.utc_now()
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
      view |> element("button", "Cancelled") |> render_click()

      assert render(view) =~ "Someone Else&#39;s Meeting"
      refute has_element?(view, "#delete-meeting-#{meeting.id}")
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

  describe "banner on a meeting whose event was deleted from the external calendar" do
    defp externally_deleted(attrs) do
      insert(
        :meeting,
        Keyword.merge(
          [
            attendee_name: "Gone From Calendar",
            status: "cancelled",
            cancelled_at: DateTime.add(DateTime.utc_now(), -1, :day),
            calendar_sync_status: "externally_deleted"
          ],
          attrs
        )
      )
    end

    defp cancelled_tab_html(conn) do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
      view |> element("button", "Cancelled") |> render_click()
      {view, render(view)}
    end

    test "tells the organiser when their cleanup will delete it, with no dismiss button", %{
      conn: conn,
      user: user
    } do
      externally_deleted(organizer_user_id: user.id, organizer_email: user.email)

      {view, html} = cancelled_tab_html(conn)

      assert html =~ "was deleted from your external calendar."
      assert html =~ "It will be deleted automatically after"
      refute has_element?(view, "button[phx-click='dismiss_calendar_sync_banner']")
    end

    test "stays visible even if it was dismissed before", %{conn: conn, user: user} do
      externally_deleted(
        organizer_user_id: user.id,
        organizer_email: user.email,
        calendar_sync_status_dismissed_at: DateTime.utc_now()
      )

      {_view, html} = cancelled_tab_html(conn)

      assert html =~ "was deleted from your external calendar."
    end

    test "leaves out the deletion date when the organiser's cleanup is off", %{
      conn: conn,
      user: user,
      profile: profile
    } do
      Profiles.update_profile_field(
        profile,
        :auto_delete_cancelled_meetings_enabled,
        false
      )

      externally_deleted(organizer_user_id: user.id, organizer_email: user.email)

      {_view, html} = cancelled_tab_html(conn)

      assert html =~ "was deleted from your external calendar."
      refute html =~ "It will be deleted automatically after"
    end

    test "tells an attendee the organiser removed it, without the organiser's date", %{
      conn: conn,
      user: user
    } do
      organizer = insert(:user)

      externally_deleted(
        organizer_user_id: organizer.id,
        organizer_email: organizer.email,
        attendee_email: user.email
      )

      {_view, html} = cancelled_tab_html(conn)

      assert html =~ "The organiser removed this meeting"
      refute html =~ "was deleted from your external calendar."
      refute html =~ "It will be deleted automatically after"
    end
  end
end
