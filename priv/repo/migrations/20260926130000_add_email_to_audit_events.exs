defmodule Tymeslot.Repo.Migrations.AddEmailToAuditEvents do
  use Ecto.Migration

  @moduledoc """
  The full email address an audit event names, shown to admins in the Audit
  log tab. `email_masked` stays for rows recorded before this column existed,
  which cannot be unmasked. NULL for those rows, so no backfill.
  """

  def change do
    alter table(:audit_events) do
      add(:email, :string)
    end
  end
end
