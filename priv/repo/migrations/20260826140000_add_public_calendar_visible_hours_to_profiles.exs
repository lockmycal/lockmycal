defmodule Tymeslot.Repo.Migrations.AddPublicCalendarVisibleHoursToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add(:public_calendar_visible_from, :time)
      add(:public_calendar_visible_to, :time)
    end
  end
end
