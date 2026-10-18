defmodule Tymeslot.Repo.Migrations.AddIcsBrandingEnabledToProfiles do
  use Ecto.Migration

  @moduledoc """
  Lets an organiser whose plan allows custom branding leave the app's
  "Scheduled with" line out of the calendar files sent about their meetings.
  Every existing profile gets `true`, which keeps the line.
  """

  # excellent_migrations:safety-assured-for-this-file column_added_with_default
  # Migrations run offline: start.sh executes them in a one-shot VM before
  # Phoenix starts, so no request contends for the lock. The default is a
  # constant, which Postgres 11+ records in the catalogue without rewriting
  # the table.

  def change do
    alter table(:profiles) do
      add(:ics_branding_enabled, :boolean, null: false, default: true)
    end
  end
end
