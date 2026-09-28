defmodule Tymeslot.Repo.Migrations.AddDeletionRequestedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:deletion_requested_at, :utc_datetime)
    end
  end
end
