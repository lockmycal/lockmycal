defmodule Tymeslot.Repo.Migrations.AddSiteBannerToAppSettings do
  use Ecto.Migration

  # Nullable columns on the app_settings singleton, same "nil = no admin
  # override" convention as every other setting here, so existing installs
  # need no backfill and keep the banner off everywhere. The message is
  # `:text` rather than `:string` because it holds admin-authored HTML that
  # can comfortably exceed varchar(255).
  def change do
    alter table(:app_settings) do
      add(:site_banner_app_enabled, :boolean)
      add(:site_banner_auth_enabled, :boolean)
      add(:site_banner_public_enabled, :boolean)
      add(:site_banner_message, :text)
      add(:site_banner_colour, :string)
    end
  end
end
