defmodule Tymeslot.Repo.Migrations.FixGoogleVideoProviderName do
  use Ecto.Migration

  def up do
    # Fix any video integrations that incorrectly use "google_calendar" instead of "google_meet"
    execute """
    UPDATE video_integrations
    SET provider = 'google_meet'
    WHERE provider = 'google_calendar'
    """
  end

  def down do
    # Revert back to incorrect name (for rollback purposes only)
    execute """
    UPDATE video_integrations
    SET provider = 'google_calendar'
    WHERE provider = 'google_meet'
    AND access_token_encrypted IS NOT NULL
    """
  end
end
