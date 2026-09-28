defmodule Tymeslot.Repo.Migrations.AddWebhookEventsTable do
  use Ecto.Migration

  def change do
    create table(:webhook_events) do
      add :stripe_event_id, :string, null: false
      add :event_type, :string, null: false
      add :processed_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:webhook_events, [:stripe_event_id])
    create index(:webhook_events, [:event_type])
    create index(:webhook_events, [:inserted_at])
  end
end
