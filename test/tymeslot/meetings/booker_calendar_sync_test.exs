defmodule Tymeslot.Meetings.BookerCalendarSyncTest do
  use Tymeslot.DataCase, async: true
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :meetings
  @moduletag :calendar
  @moduletag :integration

  import Mox
  import Tymeslot.Factory

  alias Ecto.Changeset
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.CreatedEvent
  alias Tymeslot.Integrations.CalendarManagement
  alias Tymeslot.Meetings.BookerCalendarSync
  alias Tymeslot.Meetings.MeetingQueries
  alias Tymeslot.Workers.BookerCalendarEventWorker
  alias Tymeslot.Workers.SyncCalDavCalendarWorker

  setup :verify_on_exit!

  setup do
    booker = insert(:user)
    insert(:profile, user: booker)
    integration = insert(:calendar_integration, user: booker)

    meeting =
      insert(:meeting,
        booker_user_id: booker.id,
        organizer_name: "Jana Hostitelka",
        organizer_email: "jana@example.com",
        meeting_type: "Consultation",
        attendee_message: nil
      )

    %{booker: booker, integration: integration, meeting: meeting}
  end

  defp reload(meeting) do
    {:ok, meeting} = MeetingQueries.get_meeting(meeting.id)
    meeting
  end

  defp map_copy(meeting, integration, event_id \\ "copy-event") do
    {:ok, meeting} =
      MeetingQueries.update_meeting(meeting, %{
        booker_calendar_integration_id: integration.id,
        booker_calendar_event_id: event_id
      })

    meeting
  end

  describe "a meeting that expects a calendar event" do
    test "writes the copy to the booker's calendar and records it", ctx do
      %{booker: booker, integration: integration, meeting: meeting} = ctx
      integration_id = integration.id
      booker_id = booker.id
      copy_uid = meeting.calendar_uid <> "-booker"

      expect(Tymeslot.CalendarMock, :create_event, fn data, {^integration_id, ^booker_id} ->
        assert data.uid == copy_uid
        assert data.summary =~ "Jana Hostitelka"
        assert data.description =~ "Jana Hostitelka"
        # The host shared neither their email nor their phone.
        refute data.description =~ "jana@example.com"
        # A plain personal entry: no attendee a provider could invite.
        refute Map.has_key?(data, :attendee_email)
        refute Map.has_key?(data, :organizer_email)
        {:ok, CreatedEvent.new(copy_uid)}
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)

      meeting = reload(meeting)
      assert meeting.booker_calendar_integration_id == integration.id
      assert meeting.booker_calendar_event_id == copy_uid

      # Synced right away, so the booker's calendar grid shows it now.
      assert_enqueued(
        worker: SyncCalDavCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end

    test "is written in the language the booker booked in when their account sets none",
         %{meeting: meeting} do
      {:ok, meeting} = MeetingQueries.update_meeting(meeting, %{attendee_locale: "cs"})

      expect(Tymeslot.CalendarMock, :create_event, fn data, _context ->
        assert data.summary == "Consultation s Jana Hostitelka"
        assert data.description =~ "Organizátor: Jana Hostitelka"
        {:ok, CreatedEvent.new(data.uid)}
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)
    end

    test "skips a booker with no calendar that can take it", ctx do
      %{integration: integration, meeting: meeting} = ctx
      Repo.update!(Changeset.change(integration, needs_reauth: true))

      assert :ok = BookerCalendarSync.sync(meeting.id)
      assert reload(meeting).booker_calendar_event_id == nil
      refute_enqueued(worker: SyncCalDavCalendarWorker)
    end

    test "updates a copy already written", %{integration: integration, meeting: meeting} do
      meeting = map_copy(meeting, integration)
      integration_id = integration.id

      expect(Tymeslot.CalendarMock, :update_event, fn "copy-event",
                                                      data,
                                                      {^integration_id, _user_id} ->
        assert data.start_time == meeting.start_time
        :ok
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)
    end

    test "writes the copy again when the booker deleted it", ctx do
      %{integration: integration, meeting: meeting} = ctx
      meeting = map_copy(meeting, integration)

      expect(Tymeslot.CalendarMock, :update_event, fn _id, _data, _context ->
        {:error, :not_found}
      end)

      expect(Tymeslot.CalendarMock, :create_event, fn data, _context ->
        {:ok, CreatedEvent.new(data.uid)}
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)
      assert reload(meeting).booker_calendar_event_id == meeting.calendar_uid <> "-booker"
    end
  end

  describe "the copy's title, under the booker's own \"Name bookings by\"" do
    test "is the meeting information they typed by default", ctx do
      {:ok, meeting} =
        MeetingQueries.update_meeting(ctx.meeting, %{attendee_message: "Contract review\nmore"})

      assert BookerCalendarSync.build_event_data(meeting).summary == "Contract review"
    end

    test "is the meeting type with the host when they name bookings by type", ctx do
      {:ok, _preferences} =
        CalendarManagement.save_preferences(ctx.booker.id, %{booking_title_source: "meeting_type"})

      {:ok, meeting} =
        MeetingQueries.update_meeting(ctx.meeting, %{attendee_message: "Contract review"})

      assert BookerCalendarSync.build_event_data(meeting).summary ==
               "Consultation with Jana Hostitelka"
    end
  end

  test "names the host's email and phone when the host shared them", ctx do
    {:ok, meeting} =
      MeetingQueries.update_meeting(ctx.meeting, %{
        share_organizer_email: true,
        organizer_phone: "+420777888999"
      })

    description = BookerCalendarSync.build_event_data(meeting).description

    assert description =~ "Jana Hostitelka <jana@example.com>"
    assert description =~ "+420777888999"
  end

  describe "a booker who picked a calendar within their default connection" do
    setup %{booker: booker} do
      integration =
        insert(:calendar_integration,
          user: booker,
          calendar_list: [
            %{"id" => "/cal/personal/", "name" => "Personal", "selected" => true},
            %{"id" => "/cal/work/", "name" => "Work", "selected" => true}
          ]
        )

      {:ok, _integration} =
        Calendar.set_default_integration(booker.id, integration.id, "/cal/work/")

      %{picked: integration}
    end

    test "writes the copy to that calendar and records it", ctx do
      %{booker: booker, picked: integration, meeting: meeting} = ctx
      integration_id = integration.id
      booker_id = booker.id

      expect(Tymeslot.CalendarMock, :create_event, fn data,
                                                      {^integration_id, ^booker_id, "/cal/work/"} ->
        {:ok, CreatedEvent.new(data.uid)}
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)

      meeting = reload(meeting)
      assert meeting.booker_calendar_integration_id == integration_id
      assert meeting.booker_calendar_id == "/cal/work/"
    end

    test "moves and removes the copy in the calendar it was written to", ctx do
      %{booker: booker, picked: integration, meeting: meeting} = ctx
      integration_id = integration.id
      booker_id = booker.id

      {:ok, meeting} =
        MeetingQueries.update_meeting(meeting, %{
          booker_calendar_integration_id: integration_id,
          booker_calendar_id: "/cal/work/",
          booker_calendar_event_id: "copy-event"
        })

      expect(Tymeslot.CalendarMock, :update_event, fn "copy-event",
                                                      _data,
                                                      {^integration_id, ^booker_id, "/cal/work/"} ->
        :ok
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)

      {:ok, _meeting} = MeetingQueries.update_meeting(meeting, %{status: "cancelled"})

      expect(Tymeslot.CalendarMock, :delete_event, fn "copy-event",
                                                      {^integration_id, ^booker_id, "/cal/work/"} ->
        :ok
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)
      assert reload(meeting).booker_calendar_id == nil
    end
  end

  describe "a meeting that no longer expects a calendar event" do
    test "removes the copy and forgets it", %{integration: integration, meeting: meeting} do
      meeting = map_copy(meeting, integration)
      {:ok, meeting} = MeetingQueries.update_meeting(meeting, %{status: "cancelled"})
      integration_id = integration.id

      expect(Tymeslot.CalendarMock, :delete_event, fn "copy-event", {^integration_id, _user_id} ->
        :ok
      end)

      assert :ok = BookerCalendarSync.sync(meeting.id)

      meeting = reload(meeting)
      assert meeting.booker_calendar_event_id == nil
      assert meeting.booker_calendar_integration_id == nil

      assert_enqueued(
        worker: SyncCalDavCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end

    test "does nothing when no copy was written", %{meeting: meeting} do
      {:ok, _meeting} = MeetingQueries.update_meeting(meeting, %{status: "cancelled"})

      assert :ok = BookerCalendarSync.sync(meeting.id)
    end
  end

  test "an ordinary booking is left alone" do
    meeting = insert(:meeting)

    assert :ok = BookerCalendarSync.sync(meeting.id)
  end

  describe "BookerCalendarEventWorker" do
    test "gives up quietly when the booker's calendar refuses the credentials", ctx do
      expect(Tymeslot.CalendarMock, :create_event, fn _data, _context ->
        {:error, :unauthorized}
      end)

      assert {:discard, reason} =
               perform_job(BookerCalendarEventWorker, %{"meeting_id" => ctx.meeting.id})

      assert BookerCalendarEventWorker.expected_outcome?(reason)
    end

    test "retries any other failure", ctx do
      expect(Tymeslot.CalendarMock, :create_event, fn _data, _context ->
        {:error, :connection_failed}
      end)

      assert {:error, :connection_failed} =
               perform_job(BookerCalendarEventWorker, %{"meeting_id" => ctx.meeting.id})
    end
  end
end
