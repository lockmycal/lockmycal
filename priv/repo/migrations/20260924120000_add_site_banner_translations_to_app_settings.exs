defmodule Tymeslot.Repo.Migrations.AddSiteBannerTranslationsToAppSettings do
  use Ecto.Migration

  @moduledoc """
  Per-locale overrides for the site banner message
  (`Tymeslot.AppSettings.SiteBannerTranslation`). `[]` means no translation
  exists yet, matching `meeting_types.translations` and
  `profiles.booking_text_translations`.
  """

  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  #
  # Migrations run offline: `start.sh` executes them in a one-shot VM and only
  # starts Phoenix once they finish, so the ACCESS EXCLUSIVE lock backfilling
  # the (single-row) table blocks no live traffic. Same reasoning as
  # `20260717144928_add_booking_limits_to_profiles.exs`.

  def change do
    alter table(:app_settings) do
      add(:site_banner_translations, {:array, :map}, default: [], null: false)
    end
  end
end
