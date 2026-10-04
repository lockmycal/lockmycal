defmodule Tymeslot.Repo.Migrations.IndexBookerCalendarOnMeetings do
  @moduledoc """
  Indexes the foreign keys added by `20261003090000`, so deleting a user or a
  calendar integration does not scan `meetings` to nilify them. Built
  concurrently, which cannot run inside the DDL transaction.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create_if_not_exists(index(:meetings, [:booker_user_id], concurrently: true))

    create_if_not_exists(
      index(:meetings, [:booker_calendar_integration_id], concurrently: true)
    )
  end
end
