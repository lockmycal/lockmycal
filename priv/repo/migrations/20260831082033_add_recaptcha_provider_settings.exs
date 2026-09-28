defmodule Tymeslot.Repo.Migrations.AddRecaptchaProviderSettings do
  use Ecto.Migration

  # excellent_migrations:safety-assured-for-this-file raw_sql_executed
  # excellent_migrations:safety-assured-for-this-file operation_update
  # excellent_migrations:safety-assured-for-this-file column_removed
  #
  # Replaces the boolean recaptcha_signup_enabled/recaptcha_booking_enabled
  # admin-setting columns with recaptcha_signup_provider/
  # recaptcha_booking_provider (off/google/cloudflare), now that bot
  # protection is a per-form choice of provider rather than a single on/off
  # switch. `app_settings` is a singleton table (CHECK (id = 1)), so the
  # backfill touches at most one row.

  def up do
    alter table(:app_settings) do
      add_if_not_exists(:recaptcha_signup_provider, :string)
      add_if_not_exists(:recaptcha_booking_provider, :string)
    end

    execute("""
    UPDATE app_settings
    SET recaptcha_signup_provider =
          CASE recaptcha_signup_enabled
            WHEN true THEN 'google'
            WHEN false THEN 'off'
            ELSE NULL
          END,
        recaptcha_booking_provider =
          CASE recaptcha_booking_enabled
            WHEN true THEN 'google'
            WHEN false THEN 'off'
            ELSE NULL
          END
    """)

    alter table(:app_settings) do
      remove_if_exists(:recaptcha_signup_enabled, :boolean)
      remove_if_exists(:recaptcha_booking_enabled, :boolean)
    end
  end

  def down do
    alter table(:app_settings) do
      add_if_not_exists(:recaptcha_signup_enabled, :boolean)
      add_if_not_exists(:recaptcha_booking_enabled, :boolean)
    end

    execute("""
    UPDATE app_settings
    SET recaptcha_signup_enabled =
          CASE recaptcha_signup_provider
            WHEN 'google' THEN true
            WHEN 'cloudflare' THEN true
            WHEN 'off' THEN false
            ELSE NULL
          END,
        recaptcha_booking_enabled =
          CASE recaptcha_booking_provider
            WHEN 'google' THEN true
            WHEN 'cloudflare' THEN true
            WHEN 'off' THEN false
            ELSE NULL
          END
    """)

    alter table(:app_settings) do
      remove_if_exists(:recaptcha_signup_provider, :string)
      remove_if_exists(:recaptcha_booking_provider, :string)
    end
  end
end
