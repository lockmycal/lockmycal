defmodule Tymeslot.Repo.Migrations.AddPublicCalendarEnabledToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      # A constant, non-volatile default — Postgres 11+ applies this as an
      # instant metadata-only change, no table rewrite/long lock. Defaults to
      # true so every existing host keeps their public calendar.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:public_calendar_enabled, :boolean, default: true, null: false)
    end
  end
end
