defmodule Tymeslot.Repo.Migrations.AddContactsEnabledToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      # A constant, non-volatile default — Postgres 11+ applies this as an
      # instant metadata-only change, no table rewrite/long lock.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:contacts_enabled, :boolean, default: false, null: false)
    end
  end
end
