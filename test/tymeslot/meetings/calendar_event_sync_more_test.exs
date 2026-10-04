defmodule Tymeslot.Meetings.CalendarEventSyncMoreTest do
  use Tymeslot.DataCase, async: true

  @moduletag :meetings
  @moduletag :integration

  import Mox
  import Tymeslot.Factory
  import Tymeslot.WorkerTestHelpers

  alias Ecto.UUID
  alias Tymeslot.Bookings.Orchestrator
  alias Tymeslot.Integrations.Calendar.CreatedEvent
  alias Tymeslot.Integrations.Calendar.Sync
  alias Tymeslot.Meetings.CalendarEventSync
  alias Tymeslot.Meetings.MeetingSchema
  alias TymeslotWeb.Themes.Core.MeetingManagement

  setup :verify_on_exit!

  describe "provider mapping persistence" do
    test "persists a string-key id map as provider_event_id" do
      %{meeting: meeting} = setup_calendar_scenario(uid: UUID.generate())

      expect(Tymeslot.CalendarMock, :create_event, fn _data, _ctx ->
        {:ok, CreatedEvent.from_provider_event(%{"id" => "google-event-id-abc"})}
      end)

      expect(Tymeslot.CalendarMock, :get_booking_integration_info, fn _ctx ->
        {:ok, %{integration_id: meeting.calendar_integration_id, calendar_path: "primary"}}
      end)

      assert :ok = CalendarEventSync.create(meeting.id, 1)

      updated = Repo.get(MeetingSchema, meeting.id)
      assert updated.provider_event_id == "google-event-id-abc"
    end

    test "persists an atom-key id map as provider_event_id" do
      %{meeting: meeting} = setup_calendar_scenario(uid: UUID.generate())

      expect(Tymeslot.CalendarMock, :create_event, fn _data, _ctx ->
        {:ok, CreatedEvent.from_provider_event(%{id: "outlook-event-id-xyz"})}
      end)

      expect(Tymeslot.CalendarMock, :get_booking_integration_info, fn _ctx ->
        {:ok, %{integration_id: meeting.calendar_integration_id, calendar_path: "primary"}}
      end)

      assert :ok = CalendarEventSync.create(meeting.id, 1)

      updated = Repo.get(MeetingSchema, meeting.id)
      assert updated.provider_event_id == "outlook-event-id-xyz"
    end

    test "persists a plain string UID returned from a direct create" do
      %{integration: integration, meeting: meeting} =
        setup_calendar_scenario(uid: UUID.generate())

      expect_calendar_create_success(integration.id, "caldav-uid-123")

      assert :ok = CalendarEventSync.create(meeting.id, 1)

      # Recorded as the event's identity; the booking's own uid, which the
      # attendee's links carry, is never overwritten by a provider's answer.
      updated = Repo.get(MeetingSchema, meeting.id)
      assert updated.calendar_uid == "caldav-uid-123"
      assert updated.uid == meeting.uid
    end

    test "persists string-key uid map as provider_event_id and preserves public lookups" do
      %{meeting: meeting} = setup_calendar_scenario(uid: UUID.generate())
      original_uid = meeting.uid

      expect(Tymeslot.CalendarMock, :create_event, fn _data, _ctx ->
        {:ok, CreatedEvent.from_provider_event(%{"uid" => "google-uid-abc"})}
      end)

      expect(Tymeslot.CalendarMock, :get_booking_integration_info, fn _ctx ->
        {:ok, %{integration_id: meeting.calendar_integration_id, calendar_path: "primary"}}
      end)

      assert :ok = CalendarEventSync.create(meeting.id, 1)

      updated = Repo.get!(MeetingSchema, meeting.id)
      assert updated.uid == original_uid
      assert updated.provider_event_id == "google-uid-abc"

      assert {:ok, %{id: meeting_id}} =
               MeetingManagement.validate_and_load_meeting(
                 original_uid,
                 :cancel,
                 meeting.organizer_user_id
               )

      assert meeting_id == meeting.id

      assert {:ok, %{id: ^meeting_id}} =
               Orchestrator.get_meeting_for_reschedule(
                 original_uid,
                 meeting.organizer_user_id
               )
    end

    test "persists atom-key uid map as provider_event_id and supports reconciliation" do
      %{meeting: meeting} = setup_calendar_scenario(uid: UUID.generate())
      original_uid = meeting.uid

      expect(Tymeslot.CalendarMock, :create_event, fn _data, _ctx ->
        {:ok, CreatedEvent.from_provider_event(%{uid: "google-uid-atom"})}
      end)

      expect(Tymeslot.CalendarMock, :get_booking_integration_info, fn _ctx ->
        {:ok, %{integration_id: meeting.calendar_integration_id, calendar_path: "primary"}}
      end)

      assert :ok = CalendarEventSync.create(meeting.id, 1)

      updated = Repo.get!(MeetingSchema, meeting.id)
      assert updated.uid == original_uid
      assert updated.provider_event_id == "google-uid-atom"

      assert {:ok, found} =
               Sync.find_meeting(
                 meeting.calendar_integration_id,
                 "google-uid-atom",
                 "unrelated-ical-uid"
               )

      assert found.id == meeting.id
    end

    test "prefers an explicit id when a provider map also contains uid" do
      %{meeting: meeting} = setup_calendar_scenario(uid: UUID.generate())

      expect(Tymeslot.CalendarMock, :create_event, fn _data, _ctx ->
        {:ok, CreatedEvent.from_provider_event(%{id: "provider-id", uid: "ambiguous-uid"})}
      end)

      expect(Tymeslot.CalendarMock, :get_booking_integration_info, fn _ctx ->
        {:ok, %{integration_id: meeting.calendar_integration_id, calendar_path: "primary"}}
      end)

      assert :ok = CalendarEventSync.create(meeting.id, 1)
      assert Repo.get!(MeetingSchema, meeting.id).provider_event_id == "provider-id"
    end

    test "compensates a map-shaped orphan using the explicit provider id" do
      %{meeting: meeting} = setup_calendar_scenario(uid: UUID.generate())

      expect(Tymeslot.CalendarMock, :create_event, fn _data, _ctx ->
        {:ok, CreatedEvent.from_provider_event(%{id: "exact-provider-id", uid: "ambiguous-uid"})}
      end)

      expect(Tymeslot.CalendarMock, :get_booking_integration_info, fn _ctx ->
        {:ok, %{integration_id: meeting.calendar_integration_id, calendar_path: %{invalid: true}}}
      end)

      expect(Tymeslot.CalendarMock, :delete_event, fn "exact-provider-id", _ctx -> :ok end)

      assert {:error, :calendar_mapping_persistence_failed} =
               CalendarEventSync.create(meeting.id, 1)
    end

    test "surfaces {:error, _} and compensates by deleting the orphaned event when mapping persistence fails" do
      %{integration: integration, meeting: meeting} = setup_calendar_scenario_with_paths()
      external_uid = "collides-#{System.unique_integer([:positive])}"
      original_uid = meeting.uid
      original_calendar_uid = meeting.calendar_uid

      colliding_start = DateTime.add(meeting.start_time, 1, :hour)

      insert(:meeting,
        calendar_uid: external_uid,
        calendar_integration_id: integration.id,
        organizer_user_id: meeting.organizer_user_id,
        start_time: colliding_start,
        end_time: DateTime.add(colliding_start, 60, :minute)
      )

      expect_calendar_create_success(integration.id, external_uid)

      # The provider event was created but the mapping write collides on the
      # calendar UID unique constraint. The orphaned provider event must be deleted so a
      # retry of `create` doesn't produce a duplicate.
      expect(Tymeslot.CalendarMock, :delete_event, fn ^external_uid, _ctx -> :ok end)

      assert {:error, :calendar_mapping_persistence_failed} =
               CalendarEventSync.create(meeting.id, 1)

      unchanged = Repo.get!(MeetingSchema, meeting.id)
      assert unchanged.uid == original_uid
      assert unchanged.calendar_uid == original_calendar_uid
    end

    test "tolerates a failed compensation delete and still surfaces the persistence error" do
      %{integration: integration, meeting: meeting} = setup_calendar_scenario_with_paths()
      external_uid = "collides-#{System.unique_integer([:positive])}"

      colliding_start = DateTime.add(meeting.start_time, 1, :hour)

      insert(:meeting,
        calendar_uid: external_uid,
        calendar_integration_id: integration.id,
        organizer_user_id: meeting.organizer_user_id,
        start_time: colliding_start,
        end_time: DateTime.add(colliding_start, 60, :minute)
      )

      expect_calendar_create_success(integration.id, external_uid)

      # Even if the compensating delete itself errors, the persistence error is
      # still surfaced for retry (best-effort compensation must not mask it).
      expect(Tymeslot.CalendarMock, :delete_event, fn ^external_uid, _ctx ->
        {:error, :connection_failed}
      end)

      assert {:error, :calendar_mapping_persistence_failed} =
               CalendarEventSync.create(meeting.id, 1)
    end
  end
end
