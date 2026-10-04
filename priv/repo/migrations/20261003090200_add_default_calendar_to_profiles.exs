defmodule Tymeslot.Repo.Migrations.AddDefaultCalendarToProfiles do
  @moduledoc """
  Lets a user pick which calendar of their default connection is their
  default calendar, when the connection has several.

  `profiles.default_calendar_id` names that calendar within the connection
  `primary_calendar_integration_id` points at. It is read only for a booker's
  own copy of a meeting booked elsewhere: the connection's
  `default_booking_calendar_id`, which the organiser's own bookings fall back
  to, stays as it is.

  `meetings.booker_calendar_id` records the calendar the booker's copy was
  written to, so moving or cancelling the meeting addresses that calendar.
  """

  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add(:default_calendar_id, :string, size: 1024)
    end

    alter table(:meetings) do
      add(:booker_calendar_id, :string, size: 1024)
    end
  end
end
