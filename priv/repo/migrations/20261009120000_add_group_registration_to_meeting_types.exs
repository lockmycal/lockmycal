defmodule Tymeslot.Repo.Migrations.AddGroupRegistrationToMeetingTypes do
  @moduledoc """
  Adds who may book a group meeting type (`max_participants > 1`).

    * `meeting_types.registration_mode`: `"open"` (anyone, up to the
      participant limit) or `"invite_only"` (only the addresses in
      `invited_emails`). Every existing type is open, which the default
      keeps, so nothing is backfilled.
    * `meeting_types.invited_emails`: the normalised (trimmed, lowercased)
      addresses an invite-only type accepts.

  Both only apply to a group type; a one-to-one type keeps them stored but
  ignores them (`Tymeslot.MeetingTypes.GroupRegistration`).
  """

  use Ecto.Migration

  def change do
    # Both defaults are constants, so from PostgreSQL 11 onwards each add is a
    # catalogue-only change without a table rewrite (the project requires
    # PostgreSQL 14 or newer).
    alter table(:meeting_types) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :registration_mode, :string, default: "open", null: false
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :invited_emails, {:array, :string}, default: [], null: false
    end
  end
end
