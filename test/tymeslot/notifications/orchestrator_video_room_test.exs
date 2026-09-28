defmodule Tymeslot.Notifications.OrchestratorVideoRoomTest do
  use Tymeslot.DataCase, async: false

  @moduletag :notifications

  import Tymeslot.Factory

  alias Tymeslot.Notifications.Orchestrator

  defmodule SuccessEmailService do
    @spec send_video_room_failed(map()) :: {:ok, term()}
    def send_video_room_failed(meeting) do
      send(self(), {:video_room_failed_sent, meeting})
      {:ok, :sent}
    end
  end

  defmodule FailingEmailService do
    @spec send_video_room_failed(map()) :: {:error, term()}
    def send_video_room_failed(_meeting) do
      {:error, :smtp_down}
    end
  end

  setup do
    original_service = Application.get_env(:tymeslot, :email_service_module)

    on_exit(fn ->
      restore_env(:email_service_module, original_service)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:tymeslot, key)
  defp restore_env(key, value), do: Application.put_env(:tymeslot, key, value)

  defp meeting_for_video_room(attrs \\ %{}) do
    user = insert(:user)
    insert(:profile, user: user, timezone: "Europe/London")

    insert(
      :meeting,
      Map.merge(
        %{
          organizer_user_id: user.id,
          organizer_name: "Alice",
          organizer_email: "alice@example.com",
          attendee_name: "Bob",
          attendee_email: "bob@example.com"
        },
        attrs
      )
    )
  end

  describe "handle_video_room_notifications/2 with :failed" do
    test "sends the video-room-failed email to the organizer" do
      Application.put_env(:tymeslot, :email_service_module, SuccessEmailService)
      meeting = meeting_for_video_room()

      assert {:ok, :video_room_failed_notification_sent} =
               Orchestrator.handle_video_room_notifications(meeting, :failed)

      assert_received {:video_room_failed_sent, sent_meeting}
      assert sent_meeting.id == meeting.id
    end

    test "propagates an email delivery failure" do
      Application.put_env(:tymeslot, :email_service_module, FailingEmailService)
      meeting = meeting_for_video_room()

      assert {:error, :smtp_down} =
               Orchestrator.handle_video_room_notifications(meeting, :failed)
    end
  end
end
