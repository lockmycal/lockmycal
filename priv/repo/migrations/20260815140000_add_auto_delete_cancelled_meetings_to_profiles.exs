defmodule Tymeslot.Repo.Migrations.AddAutoDeleteCancelledMeetingsToProfiles do
  @moduledoc """
  Per-user opt-in to auto-delete the organizer's own cancelled meetings once
  they've aged past a configurable number of days since cancellation. Both
  columns default every existing row to "off" / 30 days, so no data repair is
  needed and nothing changes until a user explicitly enables it.
  """

  use Ecto.Migration

  def change do
    alter table(:profiles) do
      # Both are constant, non-volatile defaults — Postgres 11+ applies these
      # as instant metadata-only changes, no table rewrite/long lock.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:auto_delete_cancelled_meetings_enabled, :boolean, default: false, null: false)
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:auto_delete_cancelled_meetings_after_days, :integer, default: 30, null: false)
    end
  end
end
