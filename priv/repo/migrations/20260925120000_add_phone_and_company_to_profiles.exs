defmodule Tymeslot.Repo.Migrations.AddPhoneAndCompanyToProfiles do
  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add(:phone, :string)
      add(:company, :string)
    end
  end
end
