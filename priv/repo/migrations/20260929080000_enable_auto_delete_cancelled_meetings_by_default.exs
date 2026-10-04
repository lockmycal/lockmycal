defmodule Tymeslot.Repo.Migrations.EnableAutoDeleteCancelledMeetingsByDefault do
  @moduledoc """
  Turns the cancelled-meeting cleanup (`DeleteCancelledMeetingsWorker`) on by
  default: new profiles get it through the column default, and every existing
  profile is switched on as well, keeping its own `after_days` (30 unless the
  user changed it). A cancelled meeting — including one auto-cancelled because
  its event was deleted from the host's calendar — then disappears on its own
  instead of lingering in the Cancelled list.

  Existing rows can't tell "never touched" from "deliberately turned off",
  since both read `false`, so the backfill switches all of them on; a user who
  wants to keep cancelled meetings turns it off again in Settings. `down/0`
  only restores the old column default: which profiles were off before is
  not recorded anywhere, so the data change can't be undone.
  """

  use Ecto.Migration

  # excellent_migrations:safety-assured-for-this-file raw_sql_executed
  #
  # Migrations run offline: `start.sh` executes them in a one-shot VM before
  # Phoenix starts, so the UPDATE over `profiles` (one row per user) blocks no
  # live traffic. Changing a constant column default is metadata-only; it is raw
  # SQL because `modify/3` would also restate the type and NOT NULL.
  def up do
    execute(
      "ALTER TABLE profiles ALTER COLUMN auto_delete_cancelled_meetings_enabled SET DEFAULT true"
    )

    execute("UPDATE profiles SET auto_delete_cancelled_meetings_enabled = true")
  end

  def down do
    execute(
      "ALTER TABLE profiles ALTER COLUMN auto_delete_cancelled_meetings_enabled SET DEFAULT false"
    )
  end
end
