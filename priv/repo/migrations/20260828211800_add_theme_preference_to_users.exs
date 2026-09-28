defmodule Tymeslot.Repo.Migrations.AddThemePreferenceToUsers do
  use Ecto.Migration

  def change do
    # Nullable: NULL means "system" — follow the browser's prefers-color-scheme.
    # A non-null value ("light" or "dark") is an explicit override. No backfill needed.
    alter table(:users) do
      add :theme_preference, :string
    end
  end
end
