defmodule Tymeslot.Repo.Migrations.AddVideoIntegrationIdToMeetings do
  use Ecto.Migration

  def change do
    alter table(:meetings) do
      add :video_integration_id, references(:video_integrations, on_delete: :nilify_all)
    end

    create index(:meetings, [:video_integration_id])
  end
end
