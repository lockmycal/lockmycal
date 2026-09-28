defmodule Tymeslot.Repo.Migrations.AddTranslationsToMeetingTypes do
  use Ecto.Migration

  @moduledoc """
  Per-locale name/description overrides for a meeting type
  (`Tymeslot.MeetingTypes.MeetingTypeTranslation`). `[]` means no
  translation exists yet, matching the two existing `embeds_many` columns
  on this table (`custom_fields`, `attachments`).
  """

  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  #
  # Migrations run offline: `start.sh` executes them in a one-shot VM and only
  # starts Phoenix once they finish, so the ACCESS EXCLUSIVE lock backfilling
  # every existing row blocks no live traffic. Same reasoning as
  # `20260717144928_add_booking_limits_to_profiles.exs`. Revisit if a
  # deployment target ever migrates against a running instance.

  def change do
    alter table(:meeting_types) do
      add(:translations, {:array, :map}, default: [], null: false)
    end
  end
end
