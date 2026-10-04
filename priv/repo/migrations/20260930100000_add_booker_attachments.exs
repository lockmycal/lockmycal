defmodule Tymeslot.Repo.Migrations.AddBookerAttachments do
  use Ecto.Migration

  # Files a booker attaches on the public booking page. The admin sets which
  # types are accepted and the size/count limits instance-wide (nullable
  # overrides, `nil` meaning "fall back to the built-in default" like every
  # other app setting); each meeting type only switches the field on or off.
  #
  # `meetings.attendee_attachments` holds the stored files' metadata. It is
  # kept apart from `attachments_snapshot`, which holds the host's own files
  # published under the public `/uploads` mount - a booker's files are private.
  def change do
    alter table(:app_settings) do
      add_if_not_exists(:booking_attachment_types, {:array, :string})
      add_if_not_exists(:max_booking_attachment_size_mb, :integer)
      add_if_not_exists(:max_booking_attachments, :integer)
    end

    alter table(:meeting_types) do
      # A constant, non-volatile default — Postgres 11+ applies this as an
      # instant metadata-only change, no table rewrite/long lock.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:allow_attachments, :boolean, default: false, null: false)
    end

    alter table(:meetings) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:attendee_attachments, {:array, :map}, null: false, default: [])
    end
  end
end
