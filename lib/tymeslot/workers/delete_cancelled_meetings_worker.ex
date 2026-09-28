defmodule Tymeslot.Workers.DeleteCancelledMeetingsWorker do
  @moduledoc """
  Nightly scan that hard-deletes each opted-in user's own cancelled meetings
  once they've aged past that user's configured retention window
  (`profiles.auto_delete_cancelled_meetings_after_days`, counted from
  `cancelled_at`).

  Runs once per night for the whole instance, but each pass only ever deletes
  a single user's own meetings — never a cross-user bulk delete. Users who
  never enabled `auto_delete_cancelled_meetings_enabled` are skipped entirely.
  """

  use Oban.Worker, queue: :default, max_attempts: 3, unique: [period: 3600]

  require Logger

  alias Tymeslot.Meetings.MeetingQueries
  alias Tymeslot.Profiles.ProfileQueries

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()
    profiles = ProfileQueries.list_auto_delete_cancelled_meetings_enabled()

    total_deleted =
      Enum.reduce(profiles, 0, fn profile, acc ->
        cutoff = DateTime.add(now, -profile.auto_delete_cancelled_meetings_after_days, :day)

        {count, _rows} =
          MeetingQueries.delete_cancelled_meetings_for_user_older_than(profile.user_id, cutoff)

        acc + count
      end)

    Logger.info("Cancelled meeting retention cleanup completed", deleted_count: total_deleted)

    :ok
  end
end
