defmodule Tymeslot.Repo.Migrations.AddBookingTextTranslationsToProfiles do
  use Ecto.Migration

  @moduledoc """
  Per-locale overrides for the profile's custom booking-page welcome text
  (`Tymeslot.Profiles.ProfileBookingTextTranslation`). `[]` means no
  translation exists yet, matching `meeting_types.translations` and
  `meeting_types.custom_fields`.
  """

  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  #
  # Migrations run offline: `start.sh` executes them in a one-shot VM and only
  # starts Phoenix once they finish, so the ACCESS EXCLUSIVE lock backfilling
  # every existing row blocks no live traffic. Same reasoning as
  # `20260717144928_add_booking_limits_to_profiles.exs`. Revisit if a
  # deployment target ever migrates against a running instance.

  def change do
    alter table(:profiles) do
      add(:booking_text_translations, {:array, :map}, default: [], null: false)
    end
  end
end
