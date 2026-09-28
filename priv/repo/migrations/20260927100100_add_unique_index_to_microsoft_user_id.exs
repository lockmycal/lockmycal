defmodule Tymeslot.Repo.Migrations.AddUniqueIndexToMicrosoftUserId do
  use Ecto.Migration

  # Concurrently, so `users` is never write-locked on an existing installation.
  # The column was only just added, so no duplicates can exist yet.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists(unique_index(:users, [:microsoft_user_id], concurrently: true))
  end
end
