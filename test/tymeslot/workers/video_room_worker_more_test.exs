defmodule Tymeslot.Workers.VideoRoomWorkerMoreTest do
  use Tymeslot.DataCase, async: false

  @moduletag :workers

  use Oban.Testing, repo: Tymeslot.Repo
  import Mox
  import Tymeslot.Factory
  import Tymeslot.WorkerTestHelpers

  alias Ecto.UUID
  alias Oban.Job
  alias Tymeslot.Meetings.MeetingQueries
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Webhooks
  alias Tymeslot.Workers.EmailWorker
  alias Tymeslot.Workers.VideoRoomWorker
  alias Tymeslot.Workers.WebhookWorker

  setup :verify_on_exit!

  describe "perform/1 - the meeting.created fan-out" do
    setup do
      scenario = setup_video_scenario()

      {:ok, webhook} =
        Webhooks.create_webhook(scenario.user.id, %{
          name: "Bookings",
          url: "https://example.com/hooks/bookings",
          events: ["meeting.created"]
        })

      Map.put(scenario, :webhook, webhook)
    end

    test "dispatches meeting.created once the room exists, not just the emails", %{
      meeting: meeting
    } do
      expect_mirotalk_success()

      assert :ok =
               perform_job(VideoRoomWorker, %{
                 "meeting_id" => meeting.id,
                 "announce" => true
               })

      # The emails were never the whole event. Holding them until the room
      # exists is the point of this job; holding the webhook and dropping it is
      # not.
      assert_enqueued(worker: EmailWorker)
      assert_enqueued(worker: WebhookWorker)
    end

    test "dispatches meeting.created when the room can never be created", %{user: user} do
      # A different slot from the scenario's own meeting: an organiser cannot
      # hold two confirmed meetings at one time, and the database says so.
      start_time = DateTime.utc_now() |> DateTime.add(3, :day) |> DateTime.truncate(:second)

      meeting =
        insert(:meeting,
          organizer_user_id: user.id,
          organizer_email: user.email,
          video_integration_id: nil,
          start_time: start_time,
          end_time: DateTime.add(start_time, 30, :minute)
        )

      stub(Tymeslot.EmailServiceMock, :send_video_room_failed, fn _meeting -> {:ok, :sent} end)

      assert {:discard, "Video integration missing"} =
               perform_job(
                 VideoRoomWorker,
                 %{"meeting_id" => meeting.id, "announce" => true},
                 attempt: 1
               )

      # The attendees get their emails without a link; the subscriber has to
      # learn about the booking all the same.
      assert_enqueued(worker: EmailWorker)
      assert_enqueued(worker: WebhookWorker)
    end

    test "stays silent when the notifications have already gone out", %{meeting: meeting} do
      expect_mirotalk_success()

      assert :ok =
               perform_job(VideoRoomWorker, %{
                 "meeting_id" => meeting.id,
                 "announce" => false
               })

      # `announce: false` means the caller already announced the booking.
      # Announcing it again would deliver the attendee a second confirmation and
      # the subscriber a duplicate event.
      refute_enqueued(worker: EmailWorker)
      refute_enqueued(worker: WebhookWorker)
    end

    test "a room arriving after recovery announced the booking does not announce it twice" do
      %{meeting: meeting} = setup_future_meeting_scenario()

      stub(Tymeslot.EmailServiceMock, :send_video_room_failed, fn _meeting -> {:ok, :sent} end)

      {:ok, _webhook} =
        Webhooks.create_webhook(meeting.organizer_user_id, %{
          name: "Late room",
          url: "https://example.com/hooks/late-room",
          events: ["meeting.created"]
        })

      stub(Tymeslot.HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end)

      # Ordinary retries are spent, so recovery announces the booking without a
      # join link rather than leave the attendees waiting on one.
      assert {:snooze, _seconds} =
               perform_job(
                 VideoRoomWorker,
                 %{"meeting_id" => meeting.id, "announce" => true},
                 attempt: 5
               )

      assert_enqueued(worker: WebhookWorker)

      # Recovery snoozes for hours, and every channel's Oban uniqueness window
      # is five minutes wide, so by the time the next attempt runs none of them
      # would suppress a repeat. Clearing the queue is what makes a second
      # fan-out visible here rather than silently deduped.
      Repo.delete_all(Job)

      # The provider comes back and a later recovery attempt gets its room. The
      # link is worth having, the second `meeting.created` is not: the
      # subscriber would see the same booking arrive twice.
      expect_mirotalk_success()

      assert :ok =
               perform_job(
                 VideoRoomWorker,
                 %{"meeting_id" => meeting.id, "announce" => true},
                 attempt: 6
               )

      refute_enqueued(worker: WebhookWorker)
      refute_enqueued(worker: EmailWorker)
    end
  end

  describe "perform/1 - idempotency" do
    test "duplicate execution is safe (idempotent)" do
      %{meeting: meeting} = setup_video_scenario()

      # First execution
      expect_mirotalk_success()
      assert :ok = perform_job(VideoRoomWorker, %{"meeting_id" => meeting.id})

      first_meeting = Repo.get(MeetingSchema, meeting.id)
      assert first_meeting.video_room_id

      # Second execution (simulates retry or duplicate job)
      # In the second execution, VideoRooms.add_video_room_to_meeting will detect
      # that a room is already attached and return {:ok, meeting} without
      # calling the video provider again.
      assert :ok = perform_job(VideoRoomWorker, %{"meeting_id" => meeting.id})

      # Meeting should still have a video room
      second_meeting = Repo.get(MeetingSchema, meeting.id)
      assert second_meeting.video_room_id == first_meeting.video_room_id
    end
  end

  defp setup_future_meeting_scenario do
    %{meeting: meeting} = setup_video_scenario()

    # Create a meeting type with a 24-hour reminder
    user = Repo.get!(Tymeslot.Auth.UserSchema, meeting.organizer_user_id)

    meeting_type =
      insert(:meeting_type, user: user, reminder_config: [%{value: 24, unit: "hours"}])

    # Ensure meeting is far in the future (e.g., 3 days)
    meeting = Repo.get!(MeetingSchema, meeting.id)
    # 3 days
    future_start = DateTime.add(DateTime.utc_now(), 259_200, :second)
    future_end = DateTime.add(future_start, 3600, :second)

    {:ok, meeting} =
      MeetingQueries.update_meeting(meeting, %{
        start_time: future_start,
        end_time: future_end,
        meeting_type_id: meeting_type.id
      })

    %{meeting: meeting, meeting_type: meeting_type}
  end

  describe "scheduling" do
    test "schedule_video_room_creation/1 enqueues job" do
      assert :ok = VideoRoomWorker.schedule_video_room_creation("123")

      assert_enqueued(
        worker: VideoRoomWorker,
        args: %{"meeting_id" => "123", "announce" => false}
      )
    end

    test "schedule_video_room_creation_with_announcement/1 enqueues job" do
      assert :ok = VideoRoomWorker.schedule_video_room_creation_with_announcement("123")

      assert_enqueued(
        worker: VideoRoomWorker,
        args: %{"meeting_id" => "123", "announce" => true}
      )
    end
  end

  describe "scheduling a reschedule's room" do
    setup do
      original = %MeetingSchema{
        id: UUID.generate(),
        start_time: ~U[2026-10-01 09:00:00Z],
        end_time: ~U[2026-10-01 10:00:00Z]
      }

      %{original: original, updated: %{original | start_time: ~U[2026-10-01 09:00:00Z]}}
    end

    test "still deduplicates a job that has not run yet", %{
      original: original,
      updated: updated
    } do
      assert :ok =
               VideoRoomWorker.schedule_video_room_creation_with_reschedule_announcement(
                 updated,
                 original
               )

      assert :ok =
               VideoRoomWorker.schedule_video_room_creation_with_reschedule_announcement(
                 updated,
                 original
               )

      assert [_one] = all_enqueued(worker: VideoRoomWorker, args: %{"meeting_id" => updated.id})
    end

    # A location-only change (Zoom to Teams) and its reversal a minute later
    # carry the same args; the second must still get its room and its notice.
    test "queues a repeat of a reschedule whose first job already finished", %{
      original: original,
      updated: updated
    } do
      assert :ok =
               VideoRoomWorker.schedule_video_room_creation_with_reschedule_announcement(
                 updated,
                 original
               )

      Repo.update_all(Oban.Job, set: [state: "completed", completed_at: DateTime.utc_now()])

      assert :ok =
               VideoRoomWorker.schedule_video_room_creation_with_reschedule_announcement(
                 updated,
                 original
               )

      assert [_repeat] =
               all_enqueued(worker: VideoRoomWorker, args: %{"meeting_id" => updated.id})
    end
  end
end
