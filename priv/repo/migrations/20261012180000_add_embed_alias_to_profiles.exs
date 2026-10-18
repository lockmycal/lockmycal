defmodule Tymeslot.Repo.Migrations.AddEmbedAliasToProfiles do
  @moduledoc """
  Adds `profiles.embed_alias`: an optional secret handle (`_` plus a random
  token) that stands in for the username in the booking widget's URLs, so the
  widget does not reveal the organiser's public booking page. Unset for every
  existing profile; the unique index follows in `20261012180100`.
  """

  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :embed_alias, :string
    end
  end
end
