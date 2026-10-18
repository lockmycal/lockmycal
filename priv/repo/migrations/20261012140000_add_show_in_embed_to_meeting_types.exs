defmodule Tymeslot.Repo.Migrations.AddShowInEmbedToMeetingTypes do
  @moduledoc """
  Adds `meeting_types.show_in_embed`: whether the type is listed in the
  organiser's embedded booking widget, independently of `is_private`, which
  hides it from the public booking page.

  Until now the widget listed exactly the public types, so a private type is
  backfilled to `false` and every other type keeps the `true` default: no
  existing widget changes what it shows.
  """

  use Ecto.Migration

  # The backfill keeps existing widgets as they are; it only touches the
  # private types, which the widget never listed.
  # excellent_migrations:safety-assured-for-this-file raw_sql_executed
  # excellent_migrations:safety-assured-for-this-file operation_update

  def up do
    # A constant default is a catalogue-only change from PostgreSQL 11 onwards
    # (the project requires PostgreSQL 14 or newer).
    alter table(:meeting_types) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :show_in_embed, :boolean, default: true, null: false
    end

    execute("UPDATE meeting_types SET show_in_embed = false WHERE is_private")
  end

  def down do
    alter table(:meeting_types) do
      # excellent_migrations:safety-assured-for-next-line column_removed
      remove :show_in_embed
    end
  end
end
