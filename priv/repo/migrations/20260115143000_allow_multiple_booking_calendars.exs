defmodule Tymeslot.Repo.Migrations.AllowMultipleBookingCalendars do
  use Ecto.Migration

  def change do
    # 1. Update meeting_types table
    alter table(:meeting_types) do
      add :calendar_integration_id, references(:calendar_integrations, on_delete: :nilify_all)
      add :target_calendar_id, :string
    end

    create index(:meeting_types, [:calendar_integration_id])

    # 2. Drop the unique constraint on calendar_integrations
    # Note: This index was created concurrently in a previous migration, 
    # but here we can drop it normally.
    drop_if_exists index(:calendar_integrations, [:user_id], name: :unique_booking_calendar_per_user)

    # 3. Backfill existing meeting types
    flush()

    execute """
    UPDATE meeting_types mt
    SET calendar_integration_id = (
      SELECT primary_calendar_integration_id 
      FROM profiles p 
      WHERE p.user_id = mt.user_id
    ),
    target_calendar_id = (
      SELECT default_booking_calendar_id 
      FROM calendar_integrations ci 
      WHERE ci.id = (
        SELECT primary_calendar_integration_id 
        FROM profiles p 
        WHERE p.user_id = mt.user_id
      )
    )
    """
  end
end
