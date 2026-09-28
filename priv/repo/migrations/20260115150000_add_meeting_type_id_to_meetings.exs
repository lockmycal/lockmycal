defmodule Tymeslot.Repo.Migrations.AddMeetingTypeIdToMeetings do
  use Ecto.Migration

  def change do
    alter table(:meetings) do
      add :meeting_type_id, references(:meeting_types, on_delete: :nilify_all)
    end

    create index(:meetings, [:meeting_type_id])
  end
end
