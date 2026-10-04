defmodule TymeslotWeb.Dashboard.CalendarGrid.BookingEventsLiveviewTest do
  @moduledoc """
  Covers Tymeslot bookings rendered natively on the calendar grid: read-only
  booking blocks with no integration connected, the booking detail modal, the
  connect-a-calendar banner, and deduplication against a synced provider copy.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :calendar
  @moduletag :live

  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Plug.Test
  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Onboarding

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")
    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user}
  end

  defp insert_booking(user, attrs \\ %{}) do
    start_time = DateTime.new!(Date.utc_today(), ~T[09:00:00], "Etc/UTC")

    defaults = %{
      organizer_user: user,
      organizer_email: user.email,
      title: "Discovery call",
      attendee_message: nil,
      attendee_name: "Ada Lovelace",
      attendee_email: "ada@example.com",
      start_time: start_time,
      end_time: DateTime.add(start_time, 3600, :second),
      status: "confirmed"
    }

    insert(:meeting, Map.merge(defaults, attrs))
  end

  describe "bookings on the grid without any integration" do
    test "renders the booking as a read-only block", %{conn: conn, user: user} do
      meeting = insert_booking(user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "Discovery call"
      assert html =~ ~s(phx-value-meeting-id="#{meeting.id}")
      assert html =~ ~s(phx-click="show_booking")

      # The block is not draggable and offers no resize handle.
      assert html =~ ~s(data-event-id="booking-#{meeting.id}")
      refute html =~ ~s(id="event-booking-#{meeting.id}) <> ~s(" data-draggable="true")
    end

    test "shows the connect-a-calendar banner instead of a blocking empty state",
         %{conn: conn, user: user} do
      # The banner defers to the setup checklist, which carries the same
      # "Connect a calendar" step, so dismiss the checklist first.
      {:ok, _user} = Onboarding.dismiss_dashboard_setup(user)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "data-testid=\"connect-calendar-banner\""
      assert html =~ "Bring your calendar into #{Config.app_name()}"
      refute html =~ "Nothing to see here"
    end

    test "defers the banner to the setup checklist while setup is incomplete",
         %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      assert html =~ "data-testid=\"onboarding-checklist\""
      refute html =~ "data-testid=\"connect-calendar-banner\""
    end

    test "hides the banner once an integration is connected", %{conn: conn, user: user} do
      insert(:calendar_integration, user: user, is_active: true)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      refute html =~ "data-testid=\"connect-calendar-banner\""
    end
  end

  describe "pending-approval styling" do
    test "renders a booking awaiting approval bold and red instead of its usual colour",
         %{conn: conn, user: user} do
      meeting = insert_booking(user, %{title: "Needs a yes", status: "awaiting_approval"})

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      block =
        html
        |> Floki.parse_document!()
        |> Floki.find(~s{[data-event-id="booking-#{meeting.id}"]})

      assert Enum.any?(Floki.attribute(block, "class"), &(&1 =~ "bg-red-50"))
      assert Enum.any?(Floki.attribute(block, "class"), &(&1 =~ "font-bold"))
      refute Enum.any?(Floki.attribute(block, "class"), &(&1 =~ "bg-primary-600"))
    end

    test "a booking awaiting approval stays red once its tentative hold has synced",
         %{conn: conn, user: user} do
      integration = insert(:calendar_integration, user: user, is_active: true)

      meeting =
        insert_booking(user, %{
          title: "Needs a yes",
          attendee_message: nil,
          status: "awaiting_approval",
          provider_event_id: "held-event"
        })

      hold =
        insert(:provider_calendar_event,
          calendar_integration: integration,
          provider_event_id: "held-event",
          summary: "Needs a yes",
          status: "tentative",
          created_by_tymeslot: true,
          start_at: meeting.start_time,
          end_at: meeting.end_time
        )

      {:ok, _lv, html} = live(conn, ~p"/dashboard")
      doc = Floki.parse_document!(html)

      block = Floki.find(doc, ~s{[data-event-id="booking-#{meeting.id}"]})
      assert Enum.any?(Floki.attribute(block, "class"), &(&1 =~ "bg-red-50"))

      # The hold itself is not drawn next to it in its calendar colour.
      assert Floki.find(doc, ~s{[data-event-id="#{hold.id}"]}) == []
    end

    test "an ordinary confirmed booking keeps its usual colour, not the red alert styling",
         %{conn: conn, user: user} do
      meeting = insert_booking(user, %{title: "Already confirmed", status: "confirmed"})

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      block =
        html
        |> Floki.parse_document!()
        |> Floki.find(~s{[data-event-id="booking-#{meeting.id}"]})

      assert Enum.any?(Floki.attribute(block, "class"), &(&1 =~ "bg-primary-600"))
      refute Enum.any?(Floki.attribute(block, "class"), &(&1 =~ "bg-red-50"))
    end
  end

  describe "booking detail modal" do
    test "opens with booking details and closes again", %{conn: conn, user: user} do
      meeting =
        insert_booking(user, %{
          description: "We should cover everything",
          attendee_message: "Looking forward to it"
        })

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> element(~s{[data-event-id="booking-#{meeting.id}"]})
        |> render_click()

      assert html =~ "booking-detail-modal"
      assert html =~ "Ada Lovelace"
      assert html =~ "ada@example.com"
      # The meeting type's description, under that label; each value starts
      # right after its tag, since a leading newline would show as a blank
      # line under `whitespace-pre-line`.
      assert html =~ "Meeting Type"
      refute html =~ "Description"
      assert html =~ ">We should cover everything</div>"
      assert html =~ ">Looking forward to it</div>"
      assert html =~ "Booked through your #{Config.app_name()} booking page"
      assert html =~ "Manage in Meetings"
      # A primary button, which keeps its colours on hover in both modes.
      assert has_element?(
               lv,
               "a.btn.btn-primary[href='/dashboard/meetings']",
               "Manage in Meetings"
             )

      refute lv
             |> element("#booking-detail-modal button", "Cancel")
             |> render_click() =~ "booking-detail-modal"
    end

    test "ignores an unknown meeting id", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("show_booking", %{"meeting-id" => "999999"})

      refute html =~ "booking-detail-modal"
    end
  end

  describe "agenda bookings lens" do
    test "filters the agenda down to bookings", %{conn: conn, user: user} do
      integration = insert(:calendar_integration, user: user, is_active: true)

      day = Date.add(Date.utc_today(), 2)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "External standup",
        start_at: DateTime.new!(day, ~T[09:00:00], "Etc/UTC"),
        end_at: DateTime.new!(day, ~T[10:00:00], "Etc/UTC"),
        all_day: false
      )

      insert_booking(user, %{
        title: "Booked discovery",
        attendee_message: nil,
        start_time: DateTime.new!(day, ~T[11:00:00], "Etc/UTC"),
        end_time: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")
      })

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      # Scope to the agenda container: other (hidden) views keep their own
      # copies of the events in the DOM.
      agenda_text = fn html ->
        html |> Floki.parse_document!() |> Floki.find("#calendar-agenda") |> Floki.text()
      end

      html = lv |> element("#calendar-grid") |> render_hook("set_view", %{"view" => "agenda"})
      assert agenda_text.(html) =~ "External standup"
      assert agenda_text.(html) =~ "Booked discovery"

      html = lv |> element(~s{[data-testid="agenda-lens-bookings"]}) |> render_click()
      refute agenda_text.(html) =~ "External standup"
      assert agenda_text.(html) =~ "Booked discovery"

      html = lv |> element(~s{[data-testid="agenda-lens-all"]}) |> render_click()
      assert agenda_text.(html) =~ "External standup"
    end
  end

  describe "booker attachments" do
    @attachment %{
      "id" => "file-1",
      "filename" => "Brief.pdf",
      "content_type" => "application/pdf",
      "byte_size" => 1_200
    }

    test "the synced copy's detail dialog lists the files with download links",
         %{conn: conn, user: user} do
      integration = insert(:calendar_integration, user: user, is_active: true)

      meeting =
        insert_booking(user, %{provider_event_id: "prov-att", attendee_attachments: [@attachment]})

      copy =
        insert(:provider_calendar_event,
          calendar_integration: integration,
          summary: "Discovery call",
          provider_event_id: "prov-att",
          created_by_tymeslot: true,
          start_at: meeting.start_time,
          end_at: meeting.end_time,
          all_day: false
        )

      {:ok, lv, html} = live(conn, ~p"/dashboard")
      assert html =~ ~s(data-testid="attachments-marker")

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("show_event", %{"event-id" => to_string(copy.id)})

      assert html =~ ~s(data-testid="event-attendee-attachments")
      assert html =~ "Brief.pdf"
      assert html =~ "/dashboard/meetings/#{meeting.id}/attachments/file-1"
    end

    test "an event with no booking behind it shows no attachments block",
         %{conn: conn, user: user} do
      integration = insert(:calendar_integration, user: user, is_active: true)

      event =
        insert(:provider_calendar_event,
          calendar_integration: integration,
          summary: "Dentist",
          provider_event_id: "own-event",
          start_at: DateTime.new!(Date.utc_today(), ~T[12:00:00], "Etc/UTC"),
          end_at: DateTime.new!(Date.utc_today(), ~T[13:00:00], "Etc/UTC"),
          all_day: false
        )

      {:ok, lv, _html} = live(conn, ~p"/dashboard")

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("show_event", %{"event-id" => to_string(event.id)})

      refute html =~ "event-attendee-attachments"
    end
  end

  describe "deduplication against a synced provider copy" do
    test "shows only the synced provider event for a written-back booking",
         %{conn: conn, user: user} do
      integration = insert(:calendar_integration, user: user, is_active: true)

      meeting = insert_booking(user, %{provider_event_id: "prov-1"})

      copy =
        insert(:provider_calendar_event,
          calendar_integration: integration,
          summary: "Discovery call (synced)",
          provider_event_id: "prov-1",
          created_by_tymeslot: true,
          start_at: meeting.start_time,
          end_at: meeting.end_time,
          all_day: false
        )

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      # The provider copy is the one block shown, titled like the booking.
      assert html =~ ~s(data-event-id="#{copy.id}")
      refute html =~ ~s(data-event-id="booking-#{meeting.id}")
      refute html =~ "Discovery call (synced)"
    end

    test "shows a CalDAV booking once, though its synced copy is keyed by href",
         %{conn: conn, user: user} do
      integration = insert(:calendar_integration, user: user, is_active: true)
      uid = "abc123@tymeslot.com"

      # The CalDAV write path stores its caller-supplied UID on the meeting (as
      # its calendar_uid) and leaves provider_event_id unset, while the synced
      # copy carries the server's href there. Matching on provider_event_id alone drew both.
      meeting = insert_booking(user, %{calendar_uid: uid, provider_event_id: nil})

      copy =
        insert(:provider_calendar_event,
          calendar_integration: integration,
          summary: "Discovery call (synced)",
          uid: uid,
          provider_event_id: "/calendars/sander/default/#{uid}.ics",
          created_by_tymeslot: true,
          start_at: meeting.start_time,
          end_at: meeting.end_time,
          all_day: false
        )

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      # The provider copy is the one block shown, titled like the booking.
      assert html =~ ~s(data-event-id="#{copy.id}")
      refute html =~ ~s(data-event-id="booking-#{meeting.id}")
      refute html =~ "Discovery call (synced)"
    end
  end
end
