defmodule TymeslotWeb.Dashboard.ThemeSettings.BrandLogoComponentTest do
  # Not async: it swaps the global feature checker.
  use TymeslotWeb.LiveCase, async: false

  @moduletag :live
  @moduletag :themes

  import Tymeslot.ConfigTestHelpers
  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.BrandLogo

  # A 1x1 PNG — the browser hook converts before upload, so the server side
  # only ever needs to accept a PNG.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
       )

  defmodule DenyBrandingChecker do
    @behaviour Tymeslot.Features.CheckerBehaviour
    @impl Tymeslot.Features.CheckerBehaviour
    def check_access(_user_id, :custom_branding_allowed), do: {:error, :insufficient_plan}
    def check_access(_user_id, _feature), do: :ok
  end

  defmodule StubPlaceholder do
    use Phoenix.LiveComponent

    @impl Phoenix.LiveComponent
    def render(assigns) do
      ~H"""
      <div id="stub-branding-placeholder">Upgrade for {@feature}</div>
      """
    end
  end

  setup :setup_dashboard_user_with_theme

  setup %{profile: profile} do
    setup_config(:tymeslot, feature_access_checker: Tymeslot.Features.DefaultAccessChecker)
    on_exit(fn -> BrandLogo.delete_all_files(profile.id) end)
    :ok
  end

  defp reload(profile) do
    {:ok, profile} = Profiles.get_profile_by_user_id(profile.user_id)
    profile
  end

  defp flash_html(lv) do
    _drain = :sys.get_state(lv.pid)
    render(lv)
  end

  test "an uploaded PNG is stored and previewed", %{conn: conn, profile: profile} do
    {:ok, lv, html} = live(conn, ~p"/dashboard/theme")
    assert html =~ "Your Logo"

    logo = file_input(lv, "#brand-logo-form", :brand_logo, [%{name: "logo.png", content: @png}])
    render_upload(logo, "logo.png")

    assert flash_html(lv) =~ "Logo updated."
    %{brand_logo_path: relative} = reload(profile)
    assert String.starts_with?(relative, "branding/profiles/#{profile.id}/")
    assert render(lv) =~ "/uploads/" <> relative
  end

  test "bytes that are not a PNG are rejected and nothing is stored",
       %{conn: conn, profile: profile} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/theme")

    logo =
      file_input(lv, "#brand-logo-form", :brand_logo, [
        %{name: "logo.png", content: "this is not an image at all"}
      ])

    render_upload(logo, "logo.png")

    assert flash_html(lv) =~ "That file is not a valid image and was not saved."
    assert reload(profile).brand_logo_path == nil
  end

  test "removing the logo clears it and the preview", %{conn: conn, profile: profile} do
    path = Path.join(System.tmp_dir!(), "brand-logo-live-#{System.unique_integer([:positive])}")
    File.write!(path, @png)
    {:ok, _stored} = BrandLogo.store(profile, path)

    {:ok, lv, html} = live(conn, ~p"/dashboard/theme")
    assert html =~ "/uploads/branding/profiles/"

    lv |> element("button[phx-click='remove_brand_logo']") |> render_click()

    html = flash_html(lv)
    assert html =~ "Logo removed."
    refute html =~ "/uploads/branding/profiles/"
    assert reload(profile).brand_logo_path == nil
  end

  test "the browser reports a conversion failure without storing anything",
       %{conn: conn, profile: profile} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/theme")

    lv |> element("#brand-logo-picker") |> render_hook("email_logo_conversion_failed", %{})

    assert flash_html(lv) =~ "That image could not be read."
    assert reload(profile).brand_logo_path == nil
  end

  test "is locked with a Pro badge when the plan does not allow it and no placeholder is registered",
       %{conn: conn} do
    setup_config(:tymeslot, :feature_placeholder_components, nil)

    setup_config(:tymeslot, feature_access_checker: DenyBrandingChecker)

    setup_config(
      :tymeslot,
      :feature_assigns,
      Keyword.put(
        Application.get_env(:tymeslot, :feature_assigns),
        :custom_branding_allowed,
        false
      )
    )

    {:ok, _lv, html} = live(conn, ~p"/dashboard/theme")

    assert html =~ "Your own logo is available on the Pro plan and higher."
    refute html =~ ~s(id="brand-logo-form")
  end

  test "shows the registered upgrade placeholder instead when the plan does not allow it",
       %{conn: conn} do
    setup_config(:tymeslot, feature_access_checker: DenyBrandingChecker)

    setup_config(
      :tymeslot,
      :feature_assigns,
      Keyword.put(
        Application.get_env(:tymeslot, :feature_assigns),
        :custom_branding_allowed,
        false
      )
    )

    setup_config(:tymeslot, :feature_placeholder_components, %{custom_branding: StubPlaceholder})

    {:ok, _lv, html} = live(conn, ~p"/dashboard/theme")

    assert html =~ "Upgrade for custom_branding"
    refute html =~ "Your own logo is available on the Pro plan and higher."
    refute html =~ ~s(id="brand-logo-form")
  end
end
