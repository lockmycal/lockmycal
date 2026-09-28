defmodule Tymeslot.Repo.Migrations.AddAllowedEmbedDomainsToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :allowed_embed_domains, {:array, :string}, default: []
    end

    create index(:profiles, [:allowed_embed_domains], using: :gin)
  end
end
