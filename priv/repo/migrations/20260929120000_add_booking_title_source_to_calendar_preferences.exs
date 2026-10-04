defmodule Tymeslot.Repo.Migrations.AddBookingTitleSourceToCalendarPreferences do
  use Ecto.Migration

  # Which text names a booking on the dashboard agenda and calendar grid: the
  # guest's "Meeting Information" or the meeting-type-based title. A constant
  # default backfills every existing row, so no data repair is needed; on
  # PostgreSQL 11+ a constant default is a metadata-only change, no rewrite.
  def change do
    alter table(:calendar_preferences) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:booking_title_source, :string, null: false, default: "meeting_info")
    end
  end
end
