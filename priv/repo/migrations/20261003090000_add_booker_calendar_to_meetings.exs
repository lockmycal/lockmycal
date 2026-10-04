defmodule Tymeslot.Repo.Migrations.AddBookerCalendarToMeetings do
  @moduledoc """
  Lets a signed-in booker have the meeting written into their own calendar.

  `meetings.booker_user_id` names the account that booked, set only when the
  booker agreed to the copy. The copy's location is recorded beside it, since
  it lives in the booker's integration, not the organiser's, and the
  organiser's own mapping columns already describe the organiser's event.

  `profiles.save_bookings_to_own_calendar` remembers the booker's answer:
  `ask` shows the choice on the booking form, `always`/`never` apply it
  without asking.

  The indexes are built concurrently by the next migration.
  """

  use Ecto.Migration

  def change do
    alter table(:meetings) do
      # New, empty, nullable columns: validating the constraint reads no rows,
      # so it holds its lock only for the catalogue change.
      # excellent_migrations:safety-assured-for-next-line column_reference_added
      add(:booker_user_id, references(:users, on_delete: :nilify_all))

      # excellent_migrations:safety-assured-for-next-line column_reference_added
      add(
        :booker_calendar_integration_id,
        references(:calendar_integrations, on_delete: :nilify_all)
      )

      add(:booker_calendar_event_id, :string, size: 1024)
    end

    alter table(:profiles) do
      # A constant, non-volatile default — Postgres 11+ applies this as an
      # instant metadata-only change, no table rewrite/long lock.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:save_bookings_to_own_calendar, :string, default: "ask", null: false)
    end
  end
end
