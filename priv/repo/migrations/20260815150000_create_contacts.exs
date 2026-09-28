defmodule Tymeslot.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  # Both assurances apply because the table is created empty in this same
  # migration: there are no rows for the index to lock out, and the reference is
  # declared as part of CREATE TABLE rather than added to a table already
  # holding data, so nothing a running deploy reads is locked. Building the
  # index concurrently is not possible here in any case, since CREATE INDEX
  # CONCURRENTLY cannot run inside the transaction a migration runs in.
  # excellent_migrations:safety-assured-for-this-file index_not_concurrently
  # excellent_migrations:safety-assured-for-this-file column_reference_added

  def change do
    create table(:contacts) do
      add(:organizer_user_id, references(:users, on_delete: :delete_all), null: false)
      add(:name, :string, null: false)
      add(:email, :string, null: false)
      add(:phone, :string)
      add(:company, :string)
      add(:note, :text)

      timestamps(type: :utc_datetime_usec)
    end

    # Named explicitly: the derived name exceeds Postgres' 63-character
    # identifier limit and would be silently truncated, leaving the index
    # under a name no later migration could predict in order to drop it.
    create(
      unique_index(:contacts, [:organizer_user_id, :email],
        name: :contacts_organizer_email_index
      )
    )
  end
end
