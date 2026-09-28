defmodule Tymeslot.Repo.Migrations.AddAuditLogSettingsToAppSettings do
  use Ecto.Migration

  # Nullable, same "nil = no admin override" convention as every other
  # setting: retention falls back to AUDIT_LOG_RETENTION_DAYS / 90 days, and
  # every audit event category keeps its built-in default.
  def change do
    alter table(:app_settings) do
      add_if_not_exists(:audit_log_retention_days, :integer)
      add_if_not_exists(:audit_log_events, :map)
    end
  end
end
