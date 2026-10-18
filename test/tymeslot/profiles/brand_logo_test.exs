defmodule Tymeslot.Profiles.BrandLogoTest do
  # Not async: it swaps the global feature checker, and `Tymeslot.Emails.BrandingTest`
  # clears the shared `branding/` upload directory.
  use Tymeslot.DataCase, async: false

  @moduletag :profiles

  import Tymeslot.ConfigTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Profiles.BrandLogo
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Profiles.ProfileSchema

  # A 1x1 PNG, the smallest thing ExImageInfo will recognise as one.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
       )

  defmodule DenyBrandingChecker do
    @behaviour Tymeslot.Features.CheckerBehaviour
    @impl Tymeslot.Features.CheckerBehaviour
    def check_access(_user_id, :custom_branding_allowed), do: {:error, :insufficient_plan}
    def check_access(_user_id, _feature), do: :ok
  end

  setup do
    setup_config(:tymeslot, feature_access_checker: Tymeslot.Features.DefaultAccessChecker)
    profile = insert(:profile)
    on_exit(fn -> BrandLogo.delete_all_files(profile.id) end)
    {:ok, profile: profile}
  end

  defp temp_file(bytes) do
    path = Path.join(System.tmp_dir!(), "brand-logo-test-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    path
  end

  defp absolute(relative),
    do: Path.join(Application.get_env(:tymeslot, :upload_directory), relative)

  defp deny_branding, do: setup_config(:tymeslot, feature_access_checker: DenyBrandingChecker)

  describe "store/2" do
    test "writes the PNG into the profile's own directory and records it", %{profile: profile} do
      assert {:ok, %ProfileSchema{brand_logo_path: relative}} =
               BrandLogo.store(profile, temp_file(@png))

      assert String.starts_with?(relative, "branding/profiles/#{profile.id}/logo-")
      assert File.read!(absolute(relative)) == @png
    end

    test "rejects bytes that are not a PNG and stores nothing", %{profile: profile} do
      assert {:error, :not_a_png} = BrandLogo.store(profile, temp_file("not an image"))

      {:ok, reloaded} = ProfileQueries.get_by_user_id(profile.user_id)
      assert reloaded.brand_logo_path == nil
    end

    test "deletes the previous logo when a replacement is stored", %{profile: profile} do
      {:ok, first} = BrandLogo.store(profile, temp_file(@png))
      {:ok, second} = BrandLogo.store(first, temp_file(@png))

      refute File.exists?(absolute(first.brand_logo_path))
      assert File.exists?(absolute(second.brand_logo_path))
    end

    test "is refused when the plan does not allow it", %{profile: profile} do
      deny_branding()

      assert {:error, :not_allowed} = BrandLogo.store(profile, temp_file(@png))
    end
  end

  describe "remove/1" do
    test "clears the path and deletes the file", %{profile: profile} do
      {:ok, stored} = BrandLogo.store(profile, temp_file(@png))

      assert {:ok, %ProfileSchema{brand_logo_path: nil}} = BrandLogo.remove(stored)
      refute File.exists?(absolute(stored.brand_logo_path))
    end
  end

  describe "url/1 and display_url/1" do
    test "are nil without a logo", %{profile: profile} do
      assert BrandLogo.url(profile) == nil
      assert BrandLogo.display_url(profile) == nil
    end

    test "point at the served upload when a logo is stored", %{profile: profile} do
      {:ok, stored} = BrandLogo.store(profile, temp_file(@png))

      assert BrandLogo.url(stored) == "/uploads/" <> stored.brand_logo_path
      assert BrandLogo.display_url(stored) == BrandLogo.url(stored)
    end

    test "display_url/1 hides a stored logo the plan no longer allows", %{profile: profile} do
      {:ok, stored} = BrandLogo.store(profile, temp_file(@png))
      deny_branding()

      assert BrandLogo.url(stored) == "/uploads/" <> stored.brand_logo_path
      assert BrandLogo.display_url(stored) == nil
    end

    test "are nil when the stored file is gone from disk", %{profile: profile} do
      {:ok, stored} = BrandLogo.store(profile, temp_file(@png))
      File.rm!(absolute(stored.brand_logo_path))

      assert BrandLogo.url(stored) == nil
    end
  end

  describe "email_logo_bytes/1" do
    test "returns the stored PNG when allowed", %{profile: profile} do
      {:ok, stored} = BrandLogo.store(profile, temp_file(@png))

      assert BrandLogo.email_logo_bytes(stored) == {:ok, @png}
    end

    test "is :error without a logo or when the plan does not allow it", %{profile: profile} do
      assert BrandLogo.email_logo_bytes(profile) == :error

      {:ok, stored} = BrandLogo.store(profile, temp_file(@png))
      deny_branding()

      assert BrandLogo.email_logo_bytes(stored) == :error
    end
  end

  describe "brand_logo_changeset/2" do
    test "rejects a path outside the profile's branding directory", %{profile: profile} do
      for path <- ["/etc/passwd", "branding/profiles/#{profile.id}/../../x.png", "avatars/x.png"] do
        changeset = ProfileSchema.brand_logo_changeset(profile, %{brand_logo_path: path})
        refute changeset.valid?, "accepted #{path}"
      end
    end
  end

  describe "delete_all_files/1" do
    test "removes the profile's logo directory", %{profile: profile} do
      {:ok, stored} = BrandLogo.store(profile, temp_file(@png))

      assert BrandLogo.delete_all_files(profile.id) == :ok
      refute File.exists?(absolute(stored.brand_logo_path))
    end
  end
end
