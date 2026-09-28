defmodule Tymeslot.Repo.Migrations.CreateWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:webhook_deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :webhook_id, references(:webhooks, on_delete: :delete_all), null: false
      add :event_type, :string, null: false
      add :meeting_id, :binary_id
      add :payload, :map, null: false
      add :response_status, :integer
      add :response_body, :text
      add :error_message, :text
      add :delivered_at, :utc_datetime
      add :attempt_count, :integer, default: 1, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:webhook_deliveries, [:webhook_id])
    create index(:webhook_deliveries, [:meeting_id])
    create index(:webhook_deliveries, [:event_type])
    create index(:webhook_deliveries, [:inserted_at])

    # Retention index: helps identify old deliveries for cleanup
    execute(
      """
      CREATE INDEX webhook_deliveries_retention_idx
      ON webhook_deliveries (inserted_at)
      """,
      "DROP INDEX webhook_deliveries_retention_idx"
    )
  end
end
