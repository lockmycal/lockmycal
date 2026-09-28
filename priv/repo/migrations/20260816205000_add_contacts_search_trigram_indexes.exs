defmodule Tymeslot.Repo.Migrations.AddContactsSearchTrigramIndexes do
  @moduledoc """
  Adds GIN trigram indexes on `contacts.name` and `contacts.email`, backing
  `ContactQueries.apply_search/2`'s `ilike(c.name, ^term) or ilike(c.email,
  ^term)` (used by both the contacts hub search box and the quick-add
  dialog's "pick from contacts" picker). A leading-wildcard `ILIKE '%term%'`
  can't use an ordinary B-tree index — trigram (`pg_trgm`) is the standard
  Postgres answer for substring search like this.

  Two separate single-column indexes rather than one composite index: the
  query ORs across both columns, and Postgres can combine two single-column
  indexes with a bitmap OR, whereas a composite index wouldn't help an OR
  across its columns the same way.

  `pg_trgm` is a standard contrib extension bundled with every mainstream
  Postgres distribution (including the managed providers this project
  targets); `CREATE EXTENSION IF NOT EXISTS` is a no-op if it's already
  enabled. Left in place on rollback — dropping a shared extension on `down`
  risks breaking any other object that came to depend on it.

  Created `concurrently` so existing traffic is not blocked during index
  build; this requires running outside a transaction.
  """

  # The only raw SQL is `CREATE EXTENSION IF NOT EXISTS pg_trgm` — a standard,
  # idempotent contrib-extension enable with no schema/data impact of its own.
  # excellent_migrations:safety-assured-for-this-file raw_sql_executed

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pg_trgm")

    create_if_not_exists(
      index(:contacts, ["name gin_trgm_ops"],
        using: "gin",
        concurrently: true,
        name: :contacts_name_trgm_index
      )
    )

    create_if_not_exists(
      index(:contacts, ["email gin_trgm_ops"],
        using: "gin",
        concurrently: true,
        name: :contacts_email_trgm_index
      )
    )
  end

  def down do
    drop_if_exists(
      index(:contacts, ["email gin_trgm_ops"],
        using: "gin",
        concurrently: true,
        name: :contacts_email_trgm_index
      )
    )

    drop_if_exists(
      index(:contacts, ["name gin_trgm_ops"],
        using: "gin",
        concurrently: true,
        name: :contacts_name_trgm_index
      )
    )
  end
end
