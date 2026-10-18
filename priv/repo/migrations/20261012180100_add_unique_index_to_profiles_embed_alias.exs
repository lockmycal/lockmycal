defmodule Tymeslot.Repo.Migrations.AddUniqueIndexToProfilesEmbedAlias do
  use Ecto.Migration

  # Concurrently, so `profiles` is never write-locked on an existing
  # installation. The column was only just added, so no duplicates can exist.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists(unique_index(:profiles, [:embed_alias], concurrently: true))
  end
end
