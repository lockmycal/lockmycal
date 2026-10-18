defmodule TymeslotWeb.Dashboard.ThemeSettings.IcsBrandingComponentTest do
  @moduledoc """
  The Appearance page's switch for the "Scheduled with <app>" line in calendar
  files: offered only while the plan allows custom branding and the instance
  adds the line, and stored on the profile.
  """
  # Not async: it swaps the global feature checker and footer link.
  use TymeslotWeb.LiveCase, async: false

  @moduletag :live
  @moduletag :themes

  import Tymeslot.ConfigTestHelpers
  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Profiles

  defmodule DenyBrandingChecker do
    @behaviour Tymeslot.Features.CheckerBehaviour
    @impl Tymeslot.Features.CheckerBehaviour
    def check_access(_user_id, :custom_branding_allowed), do: {:error, :insufficient_plan}
    def check_access(_user_id, _feature), do: :ok
  end

  @switch "button#ics-branding-toggle[role='switch']"

  setup :setup_dashboard_user_with_theme

  setup do
    setup_config(:tymeslot,
      ics_branding_url: "https://lockmycal.example.com",
      feature_access_checker: Tymeslot.Features.DefaultAccessChecker
    )
  end

  defp reload(profile) do
    {:ok, profile} = Profiles.get_profile_by_user_id(profile.user_id)
    profile
  end

  test "the line is on by default and can be switched off and on again",
       %{conn: conn, profile: profile} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/theme")

    assert has_element?(lv, "#{@switch}[aria-checked='true']")

    lv |> element(@switch) |> render_click()
    refute reload(profile).ics_branding_enabled
    assert has_element?(lv, "#{@switch}[aria-checked='false']")

    lv |> element(@switch) |> render_click()
    assert reload(profile).ics_branding_enabled
  end

  test "not offered while the plan does not allow custom branding", %{conn: conn} do
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

    {:ok, lv, _html} = live(conn, ~p"/dashboard/theme")

    refute has_element?(lv, @switch)
  end

  test "not offered on an instance that adds no line", %{conn: conn} do
    setup_config(:tymeslot, ics_branding_url: nil)
    {:ok, lv, _html} = live(conn, ~p"/dashboard/theme")

    refute has_element?(lv, @switch)
  end

  test "a forged switch-off without custom branding is refused",
       %{conn: conn, profile: profile} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/theme")
    setup_config(:tymeslot, feature_access_checker: DenyBrandingChecker)

    lv |> element(@switch) |> render_click()

    assert reload(profile).ics_branding_enabled
  end
end
