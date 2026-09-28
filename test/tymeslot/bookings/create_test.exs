defmodule Tymeslot.Bookings.CreateTest do
  @moduledoc false

  use Tymeslot.DataCase, async: false
  @moduletag :bookings

  alias Tymeslot.BookingCreateTestHelpers.MockCalendar
  alias Tymeslot.Bookings.Create
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.MeetingTypes
  alias Tymeslot.Repo

  import Tymeslot.BookingCreateTestHelpers

  # Create assigns the meeting's public identifier with UUID.uuid4/0.
  @uuid_v4 ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

  setup :setup_mock_calendar

  describe "execute/3 with calendar validation" do
    setup do
      setup_booking_test()
    end

    test "succeeds when calendar check returns :ok", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Mock calendar to return empty events (no conflicts)
      set_calendar_empty()

      assert {:ok, meeting} = Create.execute(meeting_params, form_data)
      assert meeting.uid =~ @uuid_v4
      assert meeting.attendee_name == "Test Attendee"
      assert meeting.attendee_email == "attendee@test.com"
    end

    test "fails with slot_unavailable when calendar check detects conflict", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Create a conflicting event at the same instant as the requested slot
      conflicting_event = create_conflicting_event(meeting_params)

      set_calendar_events([conflicting_event])

      # Validation should detect conflict and surface the semantic :slot_taken
      # atom — the web layer, not the domain layer, renders it to display text.
      assert {:error, :slot_taken} =
               Create.execute(meeting_params, form_data, skip_calendar_check: false)
    end

    test "succeeds when the only overlapping event is TRANSP:TRANSPARENT", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Regression for the "Joep vakantie" bug: an all-day transparent vacation
      # was blocking every booking during its span because the submit path
      # didn't filter events through CalendarEvent.blocking?/1.
      transparent_event =
        meeting_params
        |> create_conflicting_event()
        |> Map.merge(%{status: "confirmed", transparency: "transparent"})

      set_calendar_events([transparent_event])

      assert {:ok, meeting} =
               Create.execute(meeting_params, form_data, skip_calendar_check: false)

      assert meeting.uid =~ @uuid_v4
    end

    test "succeeds when the only overlapping event is cancelled", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      cancelled_event =
        meeting_params
        |> create_conflicting_event()
        |> Map.merge(%{status: "cancelled", transparency: "opaque"})

      set_calendar_events([cancelled_event])

      assert {:ok, meeting} =
               Create.execute(meeting_params, form_data, skip_calendar_check: false)

      assert meeting.uid =~ @uuid_v4
    end

    test "succeeds when calendar check times out (transport error)", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Mock calendar timeout/network error
      set_calendar_error(:timeout)

      # Should succeed despite calendar error - booking proceeds
      assert {:ok, meeting} = Create.execute(meeting_params, form_data)
      assert meeting.uid =~ @uuid_v4
      assert meeting.attendee_name == "Test Attendee"
    end

    test "succeeds when calendar check returns network error", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Mock calendar network error
      set_calendar_error(:network_error)

      # Should succeed despite calendar error
      assert {:ok, meeting} = Create.execute(meeting_params, form_data)
      assert meeting.uid =~ @uuid_v4
    end

    test "succeeds when calendar check returns connection error", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Mock calendar connection error
      set_calendar_error(:connection_failed)

      # Should succeed despite calendar error
      assert {:ok, meeting} = Create.execute(meeting_params, form_data)
      assert meeting.uid =~ @uuid_v4
    end

    test "succeeds when calendar check returns server error", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Mock calendar server error
      set_calendar_error(:server_error)

      # Should succeed despite calendar error
      assert {:ok, meeting} = Create.execute(meeting_params, form_data)
      assert meeting.uid =~ @uuid_v4
    end

    test "inherits calendar and video settings from meeting type", %{
      user: user,
      form_data: form_data
    } do
      # Set up integrations
      calendar_int = insert(:calendar_integration, user: user)
      video_int = insert(:video_integration, user: user)

      # Create meeting type with specific settings
      meeting_type =
        insert(:meeting_type,
          user: user,
          calendar_integration: calendar_int,
          target_calendar_id: "specific-cal-123",
          video_integration: video_int,
          allow_video: true
        )

      # Mock calendar behavior for this meeting type
      MockCalendar.set_integration_info(
        {:ok, %{integration_id: calendar_int.id, calendar_path: "specific-cal-123"}}
      )

      # Set mock calendar to return empty events (no conflicts)
      set_calendar_empty()

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "10:00",
        duration: "30min",
        user_timezone: "UTC",
        organizer_user_id: user.id,
        meeting_type_id: meeting_type.id
      }

      assert {:ok, meeting} = Create.execute(meeting_params, form_data)

      # Verify meeting record inherits settings
      assert meeting.meeting_type_id == meeting_type.id
      assert meeting.video_integration_id == video_int.id
      assert meeting.calendar_integration_id == calendar_int.id
      assert meeting.calendar_path == "specific-cal-123"
      assert meeting.meeting_type == meeting_type.name
    end

    test "rejects meeting_type_id that does not belong to organizer", %{
      user: user,
      form_data: form_data
    } do
      other_user = insert(:user)
      _profile = insert(:profile, user: other_user)

      other_meeting_type = insert(:meeting_type, user: other_user)

      set_calendar_empty()

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "10:30",
        duration: "30min",
        user_timezone: "UTC",
        organizer_user_id: user.id,
        meeting_type_id: other_meeting_type.id
      }

      # The domain layer surfaces the semantic :meeting_type_not_found atom —
      # the web layer, not the domain layer, renders it to display text.
      assert {:error, :meeting_type_not_found} = Create.execute(meeting_params, form_data)
    end

    test "ignores video_integration_id that does not belong to organizer", %{
      user: user,
      form_data: form_data
    } do
      other_user = insert(:user)
      _profile = insert(:profile, user: other_user)

      other_video_integration = insert(:video_integration, user: other_user)

      set_calendar_empty()

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "11:00",
        duration: "30min",
        user_timezone: "UTC",
        organizer_user_id: user.id,
        video_integration_id: other_video_integration.id
      }

      assert {:ok, meeting} = Create.execute(meeting_params, form_data)

      assert meeting.video_integration_id == nil
      assert meeting.meeting_type == "General Meeting"
    end

    test "fails when meeting type is inactive", %{
      user: user,
      form_data: form_data
    } do
      meeting_type = insert(:meeting_type, user: user, is_active: false)

      set_calendar_empty()

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "12:00",
        duration: "30min",
        user_timezone: "UTC",
        organizer_user_id: user.id,
        meeting_type_id: meeting_type.id
      }

      # The domain layer surfaces the semantic :meeting_type_inactive atom —
      # the web layer, not the domain layer, renders it to display text.
      assert {:error, :meeting_type_inactive} = Create.execute(meeting_params, form_data)
    end

    test "fails when meeting type has been deleted", %{
      user: user,
      form_data: form_data
    } do
      meeting_type = insert(:meeting_type, user: user, is_active: true)
      deleted_id = meeting_type.id

      # Delete the meeting type
      MeetingTypes.delete_meeting_type(meeting_type)

      set_calendar_empty()

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "12:00",
        duration: "30min",
        user_timezone: "UTC",
        organizer_user_id: user.id,
        meeting_type_id: deleted_id
      }

      # The domain layer surfaces the semantic :meeting_type_not_found atom —
      # the web layer, not the domain layer, renders it to display text.
      assert {:error, :meeting_type_not_found} = Create.execute(meeting_params, form_data)
    end
  end

  describe "execute_with_video_room/3 with calendar validation" do
    setup do
      setup_booking_test()
    end

    test "succeeds when calendar check times out", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Mock calendar timeout
      set_calendar_error(:timeout)

      # Should succeed despite calendar error
      assert {:ok, meeting} = Create.execute_with_video_room(meeting_params, form_data)
      assert meeting.uid =~ @uuid_v4
    end

    test "fails fast when calendar check detects conflict", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # Create a conflicting event at the same instant as the requested slot
      conflicting_event = create_conflicting_event(meeting_params)

      set_calendar_events([conflicting_event])

      # Should fail fast with the semantic :slot_taken atom
      assert {:error, :slot_taken} =
               Create.execute_with_video_room(meeting_params, form_data)
    end
  end

  describe "execute/3 telemetry" do
    setup do
      setup_booking_test()
    end

    test "emits [:tymeslot, :booking, :created] on successful free guest booking", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      set_calendar_empty()

      test_pid = self()

      :telemetry.attach(
        "test-booking-created",
        [:tymeslot, :booking, :created],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("test-booking-created") end)

      assert {:ok, _meeting} = Create.execute(meeting_params, form_data)
      assert_received {:telemetry, %{count: 1}, %{}}
    end
  end

  describe "execute/3 with custom field validation" do
    setup do
      setup_booking_test()
    end

    test "rejects booking when a required custom field answer is missing", %{
      user: user,
      form_data: form_data
    } do
      set_calendar_empty()

      snapshot = [
        %{
          "id" => "field-1",
          "type" => "short_text",
          "label" => "Company",
          "required" => true
        }
      ]

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "15:00",
        duration: "30min",
        user_timezone: "UTC",
        organizer_user_id: user.id,
        custom_fields_snapshot: snapshot,
        # No answer provided for the required field
        custom_field_answers: %{}
      }

      result = Create.execute(meeting_params, form_data)

      # The domain layer surfaces the semantic :custom_field_errors atom —
      # the web layer, not the domain layer, renders it to display text.
      assert {:error, :custom_field_errors} = result

      # Verify nothing was persisted
      assert Repo.aggregate(MeetingSchema, :count) == 0
    end

    test "accepts booking when all required custom field answers are present", %{
      user: user,
      form_data: form_data
    } do
      set_calendar_empty()

      snapshot = [
        %{
          "id" => "field-1",
          "type" => "short_text",
          "label" => "Company",
          "required" => true
        }
      ]

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "15:30",
        duration: "30min",
        user_timezone: "UTC",
        organizer_user_id: user.id,
        custom_fields_snapshot: snapshot,
        custom_field_answers: %{"field-1" => "Acme Corp"}
      }

      assert {:ok, meeting} = Create.execute(meeting_params, form_data)
      assert meeting.uid =~ @uuid_v4
    end

    test "accepts booking when there are no custom fields in the snapshot", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      set_calendar_empty()

      # No snapshot / empty snapshot — baseline behaviour must not regress
      params = Map.merge(meeting_params, %{custom_fields_snapshot: [], custom_field_answers: %{}})

      assert {:ok, meeting} = Create.execute(params, form_data)
      assert meeting.uid =~ @uuid_v4
    end
  end

  # The scheduling policy costs a profile lookup and a schedule lookup, and the
  # booking-window check, the schedule check and the conflict check all need it.
  # Resolving it per consumer is what this pins against.
  describe "execute/3 resolves the scheduling policy once" do
    setup do
      setup_booking_test()
    end

    test "the calendar conflict check adds no schedule lookup of its own", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      set_calendar_empty()

      # Hours far enough apart that the second booking cannot collide with the
      # first, buffer included.
      skipped =
        schedule_queries_during(meeting_params, form_data, "09:00", skip_calendar_check: true)

      checked =
        schedule_queries_during(meeting_params, form_data, "17:00", skip_calendar_check: false)

      assert skipped > 0, "expected the booking path to read the schedule at all"

      assert checked == skipped,
             "the conflict check re-derived the policy: #{checked} schedule reads with it, " <>
               "#{skipped} without"
    end

    defp schedule_queries_during(meeting_params, form_data, time, opts) do
      parent = self()
      ref = make_ref()
      handler_id = "booking-schedule-query-spy-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:tymeslot, :repo, :query],
        # The handler runs in the process that issued the query, so this is what
        # keeps a concurrently running test's queries out.
        fn _event, _measurements, %{source: source}, _config ->
          if self() == parent, do: send(parent, {:query_source, ref, source})
        end,
        nil
      )

      params = Map.put(meeting_params, :time, time)

      try do
        assert {:ok, _meeting} = Create.execute(params, form_data, opts)
      after
        :telemetry.detach(handler_id)
      end

      ref |> drain_query_sources([]) |> Enum.count(&(&1 == "availability_schedules"))
    end

    defp drain_query_sources(ref, acc) do
      receive do
        {:query_source, ^ref, source} -> drain_query_sources(ref, [source | acc])
      after
        0 -> acc
      end
    end
  end
end
