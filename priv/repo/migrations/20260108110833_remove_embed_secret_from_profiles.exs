defmodule Tymeslot.Repo.Migrations.RemoveEmbedSecretFromProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      remove :embed_secret_encrypted
    end
  end
end
