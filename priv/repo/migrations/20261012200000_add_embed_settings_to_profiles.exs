defmodule Tymeslot.Repo.Migrations.AddEmbedSettingsToProfiles do
  @moduledoc """
  Adds `profiles.embed_settings`: the Embed & Share page's Customise choices
  (layout, language, meeting type, background, initial height, max width), so
  they survive a reload instead of resetting with every visit. They only feed
  the embed code the dashboard generates; a widget already embedded keeps what
  its code says.
  """

  use Ecto.Migration

  def change do
    # A constant default is a catalogue-only change from PostgreSQL 11 onwards
    # (the project requires PostgreSQL 14 or newer).
    alter table(:profiles) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :embed_settings, :map, default: %{}, null: false
    end
  end
end
