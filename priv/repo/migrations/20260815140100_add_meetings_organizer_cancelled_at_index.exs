defmodule Tymeslot.Repo.Migrations.AddMeetingsOrganizerCancelledAtIndex do
  @moduledoc """
  Adds a partial composite index on `meetings(organizer_user_id, cancelled_at)`
  scoped to rows where `status = 'cancelled'`.

  Supports `MeetingQueries.delete_cancelled_meetings_for_user_older_than/2`
  (called nightly by `DeleteCancelledMeetingsWorker`), which scans one
  organizer's cancelled meetings for a `cancelled_at < cutoff` cutoff — this
  replaces a full scan of that organizer's cancelled-meeting partition with an
  index range scan.

  The existing `[:organizer_user_id]` and `[:status]` indexes are kept —
  other queries filter on either alone.

  Created `concurrently` so existing traffic is not blocked during index build.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create_if_not_exists(
      index(:meetings, [:organizer_user_id, :cancelled_at],
        where: "status = 'cancelled'",
        concurrently: true,
        name: :meetings_organizer_cancelled_at_index
      )
    )
  end

  def down do
    drop_if_exists(
      index(:meetings, [:organizer_user_id, :cancelled_at],
        concurrently: true,
        name: :meetings_organizer_cancelled_at_index
      )
    )
  end
end
