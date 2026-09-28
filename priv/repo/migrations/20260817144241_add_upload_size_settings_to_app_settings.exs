defmodule Tymeslot.Repo.Migrations.AddUploadSizeSettingsToAppSettings do
  use Ecto.Migration

  # Nullable integers (megabytes): NULL means "no DB override" — the
  # effective value then falls back to the config layer (unset by default)
  # and finally the built-in default (20MB image / 100MB video, matching
  # UploadConstraints' pre-existing hardcoded limits). Admin saving a value
  # writes a concrete positive integer.
  def change do
    alter table(:app_settings) do
      add_if_not_exists(:max_image_upload_size_mb, :integer)
      add_if_not_exists(:max_video_upload_size_mb, :integer)
    end
  end
end
