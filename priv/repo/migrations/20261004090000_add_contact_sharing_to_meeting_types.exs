defmodule Tymeslot.Repo.Migrations.AddContactSharingToMeetingTypes do
  @moduledoc """
  Lets a host choose whether a signed-in booker sees their email address and
  phone number on the meeting (their own calendar copy and dashboard).

  `meeting_types.show_email_to_bookers` and `show_phone_to_bookers` are the
  host's choice, off by default. Each meeting keeps what was agreed when it was
  booked, so a later change of the meeting type leaves existing bookings as they
  were: `meetings.share_organizer_email` for the email, which the meeting stores
  anyway, and `meetings.organizer_phone`, the host's phone, stored only when it
  was shared.
  """

  use Ecto.Migration

  def change do
    alter table(:meeting_types) do
      # Constant, non-volatile defaults — Postgres 11+ applies these as an
      # instant metadata-only change, no table rewrite/long lock.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:show_email_to_bookers, :boolean, default: false, null: false)
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:show_phone_to_bookers, :boolean, default: false, null: false)
    end

    alter table(:meetings) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add(:share_organizer_email, :boolean, default: false, null: false)
      add(:organizer_phone, :string)
    end
  end
end
