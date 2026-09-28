defmodule Tymeslot.Repo.Migrations.CreateWebhooks do
  use Ecto.Migration

  def change do
    create table(:webhooks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :url, :string, null: false
      add :secret_encrypted, :binary
      add :events, {:array, :string}, default: [], null: false
      add :is_active, :boolean, default: true, null: false
      add :last_triggered_at, :utc_datetime
      add :last_status, :string
      add :failure_count, :integer, default: 0, null: false
      add :disabled_at, :utc_datetime
      add :disabled_reason, :string

      timestamps(type: :utc_datetime)
    end

    create index(:webhooks, [:user_id])
    create index(:webhooks, [:user_id, :is_active])
  end
end
