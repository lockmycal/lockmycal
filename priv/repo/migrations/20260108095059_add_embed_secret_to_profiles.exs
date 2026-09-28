defmodule Tymeslot.Repo.Migrations.AddEmbedSecretToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :embed_secret_encrypted, :binary
    end
  end
end
