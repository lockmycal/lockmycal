defmodule Tymeslot.Repo.Migrations.AddBrandLogoPathToProfiles do
  @moduledoc """
  Adds `profiles.brand_logo_path`: the organizer's own logo, shown instead of
  the app logo on their public pages and in the emails about their meetings
  (`Tymeslot.Profiles.BrandLogo`). Stores the path relative to the upload
  directory; nil means no logo.
  """

  use Ecto.Migration

  def change do
    alter table(:profiles) do
      add :brand_logo_path, :string
    end
  end
end
