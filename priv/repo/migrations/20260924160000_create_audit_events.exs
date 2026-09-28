defmodule Tymeslot.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  # The indexes are created against a table this same migration creates, so
  # it is empty and nothing else holds a lock on it yet.
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently

  # No foreign key on user_id / actor_user_id: a security audit trail has to
  # outlive the account it describes (an account deletion is itself audited).
  # Rows go only through the retention prune.
  def change do
    create table(:audit_events) do
      add(:event_type, :string, null: false)
      add(:user_id, :bigint)
      add(:actor_user_id, :bigint)
      add(:email_masked, :string)
      add(:ip_address, :string)
      add(:user_agent, :string, size: 200)
      add(:session_id, :string)
      add(:provider, :string)
      add(:metadata, :map, null: false, default: %{})

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:audit_events, [:inserted_at]))
    create(index(:audit_events, [:user_id, :inserted_at]))
    create(index(:audit_events, [:event_type, :inserted_at]))
  end
end
