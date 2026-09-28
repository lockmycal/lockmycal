defmodule TymeslotWeb.AdminLiveTabsTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :infrastructure

  import Phoenix.LiveViewTest
  import Tymeslot.AdminPageHelpers
  import Tymeslot.ConfigTestHelpers

  setup :admin_conn

  defmodule ExtraTab do
    @moduledoc false
    @behaviour Tymeslot.Dashboard.Admin.SettingsTab

    use Phoenix.Component

    @impl Tymeslot.Dashboard.Admin.SettingsTab
    def id, do: :extra_test_tab

    @impl Tymeslot.Dashboard.Admin.SettingsTab
    def name, do: "Extra test tab"

    @impl Tymeslot.Dashboard.Admin.SettingsTab
    def render(viewer) do
      assigns = %{viewer_id: viewer.id}

      ~H"""
      <p id="extra-tab-content">viewer:{@viewer_id}</p>
      """
    end
  end

  describe "how the admin panel splits settings across tabs" do
    test "each tab renders only its own sections", %{conn: conn} do
      {:ok, _lv, auth} = live_admin_settings_tab(conn, :authentication)
      {:ok, _lv, email} = live_admin_settings_tab(conn, :email)
      {:ok, _lv, general} = live_admin_settings_tab(conn, :general)

      # Named headings still group the sections within a tab.
      assert auth =~ "Authentication"
      assert auth =~ "Bot protection"
      assert email =~ "Admin alerts"
      assert email =~ "Email branding"
      assert general =~ "Payments"
      assert general =~ "Analytics"
      assert general =~ "Localisation"

      # And a tab must not leak another tab's settings onto the page.
      refute auth =~ "Email brand name"
      refute email =~ "Password authentication"
      refute general =~ "Password authentication"
    end

    test "the settings sub-tab bar marks the active tab and switches on click", %{conn: conn} do
      {:ok, lv, html} = live_admin_settings_tab(conn, :email)

      # The active pill is the one carrying the selected styling — the
      # sub-tabs are `phx-click` (via the shared `option_toggle` component),
      # not links, so there's no `href` to assert on.
      assert html =~ ~r/phx-value-option="email"[^>]*class="[^"]*bg-primary-600/

      html =
        lv
        |> with_target("#admin-hub")
        |> render_click("switch_settings_tab", %{"option" => "general"})

      assert html =~ "Payments"
      refute html =~ "Admin alerts"
    end
  end

  describe "registered extension tabs" do
    test "render after the built-in tabs and show their own content", %{conn: conn} do
      with_config(:tymeslot, :admin_settings_extra_tabs, [ExtraTab])

      {:ok, lv, html} = live_admin_settings_tab(conn, :general)

      assert html =~ "Extra test tab"
      refute html =~ "extra-tab-content"

      html =
        lv
        |> with_target("#admin-hub")
        |> render_click("switch_settings_tab", %{"option" => "extra_test_tab"})

      assert html =~ ~r/extra-tab-content[^>]*>viewer:\d+/
      refute html =~ "Payments"
      refute html =~ "override the matching environment variables"
    end

    test "none are shown when none are registered", %{conn: conn} do
      {:ok, _lv, html} = live_admin_settings_tab(conn, :general)

      refute html =~ "Extra test tab"
    end
  end
end
