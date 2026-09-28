defmodule Tymeslot.Repo.Migrations.AddMicrosoftSignInColumns do
  use Ecto.Migration

  # Sign-in with a Microsoft account: the account's stable ID at Microsoft
  # (the OIDC `sub`), and the admin override for the toggle, `nil` meaning
  # "fall back to ENABLE_MICROSOFT_AUTH" like the other SSO toggles. Both are
  # nullable with no default, a metadata-only change. The unique index on
  # `microsoft_user_id` is built concurrently in the next migration.

  def change do
    alter table(:users) do
      add_if_not_exists(:microsoft_user_id, :string)
    end

    alter table(:app_settings) do
      add_if_not_exists(:microsoft_auth_enabled, :boolean)
    end
  end
end
