defmodule Tymeslot.Workers.DeleteCancelledMeetingsWorkerTest do
  @moduledoc """
  Drives the nightly scan that hard-deletes each opted-in user's own
  cancelled meetings once they've aged past that user's configured
  retention window.
  """

  use Tymeslot.DataCase, async: true
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :workers

  import Tymeslot.MeetingTestHelpers

  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Workers.DeleteCancelledMeetingsWorker

  test "deletes a cancelled meeting older than the user's configured retention" do
    %{user: user} =
      create_user_with_profile(%{
        auto_delete_cancelled_meetings_enabled: true,
        auto_delete_cancelled_meetings_after_days: 30
      })

    old = insert_cancelled(user, -1, cancelled_ago_days: 31)

    assert :ok = perform_job(DeleteCancelledMeetingsWorker, %{})

    refute Repo.get(MeetingSchema, old.id)
  end

  test "keeps a cancelled meeting that hasn't aged past the retention window yet" do
    %{user: user} =
      create_user_with_profile(%{
        auto_delete_cancelled_meetings_enabled: true,
        auto_delete_cancelled_meetings_after_days: 30
      })

    recent = insert_cancelled(user, -2, cancelled_ago_days: 10)

    assert :ok = perform_job(DeleteCancelledMeetingsWorker, %{})

    assert Repo.get(MeetingSchema, recent.id)
  end

  test "ignores a non-cancelled meeting even if it's old" do
    %{user: user} =
      create_user_with_profile(%{
        auto_delete_cancelled_meetings_enabled: true,
        auto_delete_cancelled_meetings_after_days: 30
      })

    confirmed =
      insert_meeting_for_user(user, %{
        status: "confirmed",
        start_offset: -40 * 86_400,
        duration: 1800
      })

    assert :ok = perform_job(DeleteCancelledMeetingsWorker, %{})

    assert Repo.get(MeetingSchema, confirmed.id)
  end

  test "skips users who turned auto-delete off" do
    %{user: user} = create_user_with_profile(%{auto_delete_cancelled_meetings_enabled: false})

    old = insert_cancelled(user, -3, cancelled_ago_days: 365)

    assert :ok = perform_job(DeleteCancelledMeetingsWorker, %{})

    assert Repo.get(MeetingSchema, old.id)
  end

  test "respects each user's own retention window independently" do
    %{user: short_window_user} =
      create_user_with_profile(%{
        auto_delete_cancelled_meetings_enabled: true,
        auto_delete_cancelled_meetings_after_days: 5
      })

    %{user: long_window_user} =
      create_user_with_profile(%{
        auto_delete_cancelled_meetings_enabled: true,
        auto_delete_cancelled_meetings_after_days: 90
      })

    due = insert_cancelled(short_window_user, -4, cancelled_ago_days: 10)
    not_due = insert_cancelled(long_window_user, -5, cancelled_ago_days: 10)

    assert :ok = perform_job(DeleteCancelledMeetingsWorker, %{})

    refute Repo.get(MeetingSchema, due.id)
    assert Repo.get(MeetingSchema, not_due.id)
  end

  test "never touches another user's meetings, even one it's cancelled and overdue" do
    %{user: enabled_user} =
      create_user_with_profile(%{
        auto_delete_cancelled_meetings_enabled: true,
        auto_delete_cancelled_meetings_after_days: 1
      })

    %{user: other_user} = create_user_with_profile()

    own_meeting = insert_cancelled(enabled_user, -6, cancelled_ago_days: 30)
    other_users_meeting = insert_cancelled(other_user, -7, cancelled_ago_days: 30)

    assert :ok = perform_job(DeleteCancelledMeetingsWorker, %{})

    refute Repo.get(MeetingSchema, own_meeting.id)
    assert Repo.get(MeetingSchema, other_users_meeting.id)
  end

  # `days_out` keeps each meeting in its own slot: a unique index forbids two
  # confirmed meetings for the same organiser at the same time (not relevant
  # here since these are all cancelled, but kept for consistency with
  # OrphanedVideoRoomScanWorkerTest's helper).
  defp insert_cancelled(user, days_out, opts) do
    cancelled_ago_days = Keyword.fetch!(opts, :cancelled_ago_days)
    now = DateTime.utc_now(:second)

    insert_meeting_for_user(user, %{
      start_offset: days_out * 86_400,
      duration: 1800,
      status: "cancelled",
      cancelled_at: DateTime.add(now, -cancelled_ago_days, :day)
    })
  end
end
