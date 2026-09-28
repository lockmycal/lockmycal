defmodule Tymeslot.Repo.Migrations.AddUniqueIndexToConfirmedMeetings do
  use Ecto.Migration

  def change do
    # Add a partial unique index to prevent the same organizer from having two confirmed
    # meetings at the exact same start time. This is a hardware-level guarantee for
    # double-booking prevention.
    create unique_index(:meetings, [:organizer_user_id, :start_time],
             where: "status = 'confirmed' AND organizer_user_id IS NOT NULL",
             name: :unique_confirmed_meeting_per_organizer_at_time
           )
  end
end
