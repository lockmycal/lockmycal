defmodule Tymeslot.Repo.Migrations.AddMaxBookedMinutesToWeeklyAvailability do
  use Ecto.Migration

  @moduledoc """
  Per-weekday cap on how many minutes of bookings a host accepts on that day
  of a schedule. NULL means no limit, so existing rows need no backfill and
  the check constraint holds for all current data.
  """

  # excellent_migrations:safety-assured-for-this-file check_constraint_added
  #
  # The constraint covers a column added in this same migration, so every
  # existing row is NULL and satisfies `IS NULL OR … > 0` — the validation
  # scan cannot fail. Migrations run offline (see
  # `AddBookingLimitsToProfiles`), so the lock blocks no traffic.

  def change do
    alter table(:weekly_availability) do
      add(:max_booked_minutes, :integer)
    end

    create(
      constraint(:weekly_availability, :weekly_availability_max_booked_minutes_positive,
        check: "max_booked_minutes IS NULL OR max_booked_minutes > 0"
      )
    )
  end
end
