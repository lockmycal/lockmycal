defmodule TymeslotWeb.Dashboard.OverviewAgendaTest do
  @moduledoc """
  Renders the dashboard overview and asserts the live agenda widget replaces the
  old Upcoming Meetings / Quick Actions widgets.
  """
  use TymeslotWeb.ConnCase, async: true

  @moduletag :live
  @moduletag :calendar

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Integrations.Calendar.EventColour

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now(:second))
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "renders the agenda with the user's next appointment", %{conn: conn, user: user} do
    # In progress right now, so it is today's whatever the time of day.
    now = DateTime.utc_now(:second)

    insert(:meeting,
      organizer_email: user.email,
      start_time: DateTime.add(now, -30 * 60, :second),
      end_time: DateTime.add(now, 30 * 60, :second),
      status: "confirmed",
      title: "Quarterly review",
      attendee_message: nil
    )

    {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

    assert html =~ "Your day"
    assert html =~ "Up next"
    assert html =~ "Quarterly review"

    # The cockpit carries the live countdown hook for this appointment.
    assert html =~ "agenda-countdown-"

    # The replaced widgets are gone.
    refute html =~ "Quick Actions"
    refute html =~ "Upcoming Meetings"
  end

  test "lists every tomorrow appointment in its own block, not in today's cockpit",
       %{conn: conn, user: user} do
    tomorrow = Date.add(Date.utc_today(), 1)
    first = DateTime.new!(tomorrow, ~T[09:30:00], "Etc/UTC")
    later = DateTime.new!(tomorrow, ~T[14:00:00], "Etc/UTC")

    insert(:meeting,
      organizer_email: user.email,
      start_time: first,
      end_time: DateTime.add(first, 3600, :second),
      status: "confirmed",
      title: "Team retro",
      attendee_message: nil
    )

    insert(:meeting,
      organizer_email: user.email,
      start_time: later,
      end_time: DateTime.add(later, 3600, :second),
      status: "confirmed",
      title: "Roadmap review",
      attendee_message: nil
    )

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    tomorrow_block = view |> element("#overview-tomorrow") |> render()
    assert tomorrow_block =~ "Coming up tomorrow"
    assert tomorrow_block =~ "Team retro"
    assert tomorrow_block =~ "Roadmap review"

    # The cockpit only features today's next appointment.
    today_block = view |> element("#overview-today") |> render()
    assert today_block =~ "Your day today"
    refute today_block =~ "agenda-countdown-"
    assert today_block =~ "Nothing on your plate today."
  end

  test "rows name their calendar instead of a generic source label",
       %{conn: conn, user: user} do
    integration = insert(:calendar_integration, user: user, name: "Pavliks.eu")
    tomorrow = Date.add(Date.utc_today(), 1)

    insert(:provider_calendar_event,
      calendar_integration: integration,
      summary: "Sync meeting",
      start_at: DateTime.new!(tomorrow, ~T[09:00:00], "Etc/UTC"),
      end_at: DateTime.new!(tomorrow, ~T[10:00:00], "Etc/UTC"),
      all_day: false
    )

    insert(:meeting,
      organizer_email: user.email,
      start_time: DateTime.new!(tomorrow, ~T[12:00:00], "Etc/UTC"),
      end_time: DateTime.new!(tomorrow, ~T[13:00:00], "Etc/UTC"),
      status: "confirmed",
      title: "Client call",
      attendee_message: nil
    )

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")
    tomorrow_block = view |> element("#overview-tomorrow") |> render()

    assert tomorrow_block =~ "Pavliks.eu"
    # A booking in no connected calendar carries the app's name.
    assert tomorrow_block =~ Config.app_name()
    refute tomorrow_block =~ "Booking"
  end

  test "keeps a next appointment beyond tomorrow in sight, dated", %{conn: conn, user: user} do
    later = DateTime.new!(Date.add(Date.utc_today(), 3), ~T[10:00:00], "Etc/UTC")

    insert(:meeting,
      organizer_email: user.email,
      start_time: later,
      end_time: DateTime.add(later, 3600, :second),
      status: "confirmed",
      title: "Board meeting",
      attendee_message: nil
    )

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    tomorrow_block = view |> element("#overview-tomorrow") |> render()
    assert tomorrow_block =~ "Nothing scheduled for tomorrow."
    assert tomorrow_block =~ "Next appointment"
    assert tomorrow_block =~ "Board meeting"
  end

  test "shows the empty state and connect-a-calendar nudge when nothing is scheduled",
       %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

    assert html =~ "Nothing on your plate today."
    assert html =~ "Nothing scheduled for tomorrow."
    assert html =~ "Connect a calendar to see your whole schedule here"
  end

  test "clicking a booking opens it in the calendar's booking detail",
       %{conn: conn, user: user} do
    tomorrow = Date.add(Date.utc_today(), 1)
    start = DateTime.new!(tomorrow, ~T[12:00:00], "Etc/UTC")

    meeting =
      insert(:meeting,
        organizer_user: user,
        organizer_email: user.email,
        start_time: start,
        end_time: DateTime.add(start, 45 * 60, :second),
        status: "confirmed",
        title: "Quarterly review",
        attendee_message: nil,
        attendee_name: "Dana Lee"
      )

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    path = open_in_calendar(view, "Quarterly review")
    assert path == ~p"/dashboard?#{[booking: meeting.id, date: Date.to_iso8601(tomorrow)]}"

    {:ok, calendar, html} = live(conn, path)

    assert html =~ ~s(id="booking-detail-modal")
    assert html =~ "Dana Lee"

    # Closing it returns to the Overview it was opened from.
    calendar
    |> element(~s(#booking-detail-modal button[aria-label="Close modal"]))
    |> render_click()

    assert_redirect(calendar, ~p"/dashboard/overview")
  end

  test "the 60s agenda tick refreshes the agenda without a page reload",
       %{conn: conn, user: user} do
    {:ok, view, html} = live(conn, ~p"/dashboard/overview")

    assert html =~ "Nothing scheduled for tomorrow."

    # Inserted after mount, so it can only appear once the tick re-fetches.
    tomorrow = Date.add(Date.utc_today(), 1)
    start = DateTime.new!(tomorrow, ~T[12:00:00], "Etc/UTC")

    insert(:meeting,
      organizer_email: user.email,
      start_time: start,
      end_time: DateTime.add(start, 3600, :second),
      status: "confirmed",
      title: "Freshly booked",
      attendee_message: nil
    )

    send(view.pid, :agenda_tick)
    html = render(view)

    assert html =~ "Freshly booked"
    refute html =~ "Nothing scheduled for tomorrow."

    # A second tick (mirroring the rescheduled timer firing again) is still a
    # clean no-op re-render, not a crash or a stacked/duplicate refresh.
    send(view.pid, :agenda_tick)
    html = render(view)
    assert html =~ "Freshly booked"
    assert Process.alive?(view.pid)
  end

  test "clicking a synced event opens it in the calendar's event detail",
       %{conn: conn, user: user} do
    tomorrow = Date.add(Date.utc_today(), 1)
    start = DateTime.new!(tomorrow, ~T[12:00:00], "Etc/UTC")
    integration = insert(:calendar_integration, user: user, name: "Work Google")

    event =
      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Design sync",
        start_at: start,
        end_at: DateTime.add(start, 3600, :second),
        all_day: false
      )

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    path = open_in_calendar(view, "Design sync")
    assert path == ~p"/dashboard?#{[event: event.id, date: Date.to_iso8601(tomorrow)]}"

    {:ok, calendar, html} = live(conn, path)

    assert html =~ ~s(id="event-detail-modal")
    assert html =~ "Design sync"

    calendar
    |> element(~s(#event-detail-modal button[aria-label="Close modal"]))
    |> render_click()

    assert_redirect(calendar, ~p"/dashboard/overview")
  end

  test "a detail opened on the calendar itself closes onto the calendar",
       %{conn: conn, user: user} do
    start = DateTime.new!(Date.utc_today(), ~T[12:00:00], "Etc/UTC")

    meeting =
      insert(:meeting,
        organizer_user: user,
        organizer_email: user.email,
        start_time: start,
        end_time: DateTime.add(start, 3600, :second),
        status: "confirmed",
        attendee_message: nil
      )

    {:ok, calendar, _html} = live(conn, ~p"/dashboard")

    calendar
    |> element(~s([data-event-id="booking-#{meeting.id}"][phx-click="show_booking"]))
    |> render_click()

    refute calendar
           |> element(~s(#booking-detail-modal button[aria-label="Close modal"]))
           |> render_click() =~ ~s(id="booking-detail-modal")

    refute_redirected(calendar, ~p"/dashboard/overview")
  end

  test "a booking synced to a calendar opens as its calendar copy",
       %{conn: conn, user: user} do
    tomorrow = Date.add(Date.utc_today(), 1)
    start = DateTime.new!(tomorrow, ~T[12:00:00], "Etc/UTC")
    integration = insert(:calendar_integration, user: user)

    meeting =
      insert(:meeting,
        organizer_user: user,
        organizer_email: user.email,
        start_time: start,
        end_time: DateTime.add(start, 3600, :second),
        status: "confirmed",
        title: "Synced review",
        attendee_message: nil,
        provider_event_id: "google-synced-1"
      )

    insert(:provider_calendar_event,
      calendar_integration: integration,
      summary: "Synced review",
      provider_event_id: "google-synced-1",
      start_at: start,
      end_at: DateTime.add(start, 3600, :second),
      all_day: false
    )

    {:ok, _calendar, html} =
      live(conn, ~p"/dashboard?#{[booking: meeting.id, date: Date.to_iso8601(tomorrow)]}")

    assert html =~ ~s(id="event-detail-modal")
    refute html =~ ~s(id="booking-detail-modal")
  end

  describe "a booking the user made on someone else's page" do
    setup %{user: user} do
      tomorrow = Date.add(Date.utc_today(), 1)
      start = DateTime.new!(tomorrow, ~T[12:00:00], "Etc/UTC")
      integration = insert(:calendar_integration, user: user)
      host = insert(:user)

      meeting =
        insert(:meeting,
          organizer_user: host,
          organizer_email: host.email,
          attendee_email: user.email,
          start_time: start,
          end_time: DateTime.add(start, 3600, :second),
          status: "confirmed",
          booker_user_id: user.id,
          booker_calendar_integration_id: integration.id,
          booker_calendar_event_id: "booked-elsewhere-booker"
        )

      %{tomorrow: tomorrow, start: start, integration: integration, meeting: meeting}
    end

    test "opens as the copy written to their calendar", ctx do
      insert(:provider_calendar_event,
        calendar_integration: ctx.integration,
        uid: ctx.meeting.booker_calendar_event_id,
        summary: "Consultation with the host",
        start_at: ctx.start,
        end_at: DateTime.add(ctx.start, 3600, :second),
        all_day: false
      )

      {:ok, _calendar, html} =
        live(
          ctx.conn,
          ~p"/dashboard?#{[booking: ctx.meeting.id, date: Date.to_iso8601(ctx.tomorrow)]}"
        )

      assert html =~ ~s(id="event-detail-modal")
      assert html =~ "Consultation with the host"
    end

    test "a meeting of someone else's opens nothing", ctx do
      stranger =
        insert(:meeting, start_time: ctx.start, end_time: DateTime.add(ctx.start, 3600, :second))

      {:ok, _calendar, html} =
        live(
          ctx.conn,
          ~p"/dashboard?#{[booking: stranger.id, date: Date.to_iso8601(ctx.tomorrow)]}"
        )

      refute html =~ ~s(id="event-detail-modal")
      refute html =~ ~s(id="booking-detail-modal")
    end
  end

  describe "per-event colour" do
    test "renders the palette colour on an all-day event pill", %{conn: conn, user: user} do
      today = Date.utc_today()
      integration = insert(:calendar_integration, user: user)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Company offsite",
        uid: "uid-allday-colour",
        colour: "blueberry",
        all_day: true,
        start_date: today,
        end_date: Date.add(today, 1),
        start_at: nil,
        end_at: nil
      )

      {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

      assert html =~ "Company offsite"
      assert html =~ EventColour.tailwind_class("blueberry")
    end

    test "renders the palette colour on a tomorrow peek row", %{conn: conn, user: user} do
      tomorrow = Date.add(Date.utc_today(), 1)
      # An earlier booking becomes the cockpit hero, so the coloured event lands
      # in the tomorrow peek rather than the (brand-gradient) cockpit.
      early = DateTime.new!(tomorrow, ~T[09:00:00], "Etc/UTC")

      insert(:meeting,
        organizer_email: user.email,
        start_time: early,
        end_time: DateTime.add(early, 3600, :second),
        status: "confirmed",
        title: "Standup",
        attendee_message: nil
      )

      integration = insert(:calendar_integration, user: user)
      later = DateTime.new!(tomorrow, ~T[15:00:00], "Etc/UTC")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Design review",
        uid: "uid-peek-colour",
        colour: "blueberry",
        all_day: false,
        start_at: later,
        end_at: DateTime.add(later, 3600, :second)
      )

      {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

      assert html =~ "Design review"
      assert html =~ EventColour.tailwind_class("blueberry")
    end
  end

  describe "bookings awaiting approval" do
    test "are listed red and marked, but not featured in the cockpit",
         %{conn: conn, user: user} do
      tomorrow = Date.add(Date.utc_today(), 1)
      start = DateTime.new!(tomorrow, ~T[09:00:00], "Etc/UTC")

      insert(:meeting,
        organizer_email: user.email,
        start_time: start,
        end_time: DateTime.add(start, 3600, :second),
        status: "awaiting_approval",
        title: "Consultation with Jane",
        attendee_message: "Kitchen remodel quote"
      )

      {:ok, view, html} = live(conn, ~p"/dashboard/overview")

      refute html =~ "Up next"

      tomorrow_block = view |> element("#overview-tomorrow") |> render()
      assert tomorrow_block =~ "Kitchen remodel quote"
      refute tomorrow_block =~ "Consultation with Jane"
      assert tomorrow_block =~ "Awaiting approval"
      assert tomorrow_block =~ "border-red-300"

      assert open_in_calendar(view, "Kitchen remodel quote") =~ "booking="
    end
  end

  # Clicks the agenda entry titled `title` and returns the calendar path it
  # navigates to.
  defp open_in_calendar(view, title) do
    assert {:error, {:live_redirect, %{to: path}}} =
             view
             |> element(~s([aria-label="View details for #{title}"]))
             |> render_click()

    path
  end
end
