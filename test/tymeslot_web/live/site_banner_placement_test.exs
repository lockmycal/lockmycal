defmodule TymeslotWeb.Live.SiteBannerPlacementTest do
  @moduledoc """
  Pins where the admin-configured site banner (`Tymeslot.SiteBanner`) renders:
  each of the three surfaces follows only its own switch, the banner renders
  exactly once per page (dashboard pages render it inside `DashboardLayout`,
  not also in the root layout), and it never appears in an iframe embed.
  """
  use TymeslotWeb.LiveCase, async: false

  @moduletag :ui
  @moduletag :live
  @moduletag :integration

  import Tymeslot.AppSettingsEnvHelpers
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.AppSettings
  alias Tymeslot.Infrastructure.DashboardCache

  @message "Banner placement canary"

  setup :restore_app_settings_env

  setup_all do
    case Process.whereis(DashboardCache) do
      nil -> start_supervised!(DashboardCache)
      _pid -> :ok
    end

    :ok
  end

  setup do
    {:ok, _settings} = AppSettings.update(%{site_banner_message: @message})
    :ok
  end

  describe "auth pages" do
    test "show the banner only while the auth switch is on", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/auth/login")
      refute html =~ @message

      {:ok, _settings} = AppSettings.update(%{site_banner_auth_enabled: true})

      {:ok, _view, html} = live(conn, ~p"/auth/login")
      assert count(html) == 1
      assert html =~ "data-site-banner-dismiss"
      assert html =~ "ts:site-banner-dismissed"
    end

    test "show the translation for the visitor's language", %{conn: conn} do
      {:ok, _settings} =
        AppSettings.update(%{
          site_banner_auth_enabled: true,
          site_banner_translations: [%{"locale" => "de", "message" => "Banner auf Deutsch"}]
        })

      {:ok, _view, html} = live(conn, ~p"/auth/login?locale=de")
      assert html =~ "Banner auf Deutsch"
      refute html =~ @message

      {:ok, _view, html} = live(conn, ~p"/auth/login?locale=en")
      assert html =~ @message
    end

    test "ignore the other surfaces' switches", %{conn: conn} do
      {:ok, _settings} =
        AppSettings.update(%{site_banner_app_enabled: true, site_banner_public_enabled: true})

      {:ok, _view, html} = live(conn, ~p"/auth/login")
      refute html =~ @message
    end
  end

  describe "dashboard" do
    setup %{conn: conn} do
      DashboardCache.clear_all()

      user =
        insert(:user,
          onboarding_completed_at: DateTime.utc_now(),
          dashboard_tour_seen_at: DateTime.utc_now()
        )

      insert(:profile, user: user, username: "bannerhost")

      {:ok, conn: conn |> init_test_session(%{}) |> log_in_user(user)}
    end

    test "renders the banner exactly once, inside the LiveView", %{conn: conn} do
      {:ok, _settings} = AppSettings.update(%{site_banner_app_enabled: true})

      {:ok, view, static_html} = live(conn, ~p"/dashboard/overview")

      assert count(static_html) == 1
      assert count(render(view)) == 1
    end

    test "is hidden while the app switch is off", %{conn: conn} do
      {:ok, _settings} = AppSettings.update(%{site_banner_auth_enabled: true})

      {:ok, _view, static_html} = live(conn, ~p"/dashboard/overview")
      refute static_html =~ @message
    end
  end

  describe "public booking page" do
    setup do
      user = insert(:user)

      insert(:profile,
        user: user,
        username: "bannerpublic",
        allowed_embed_domains: ["example.com"]
      )

      Mox.stub(Tymeslot.CalendarMock, :get_events_for_range_fresh, fn _integration,
                                                                      _range_start,
                                                                      _range_end ->
        {:ok, []}
      end)

      insert(:calendar_integration, user: user, provider: "google", is_active: true)
      insert(:meeting_type, user: user, name: "Test", duration_minutes: 30, is_active: true)

      :ok
    end

    test "shows the banner only while the public switch is on", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bannerpublic")
      refute html =~ @message

      {:ok, _settings} = AppSettings.update(%{site_banner_public_enabled: true})

      {:ok, _view, html} = live(conn, "/bannerpublic")
      assert count(html) == 1
    end

    test "never shows the banner inside an iframe embed", %{conn: conn} do
      {:ok, _settings} = AppSettings.update(%{site_banner_public_enabled: true})

      conn = get(conn, "/bannerpublic?embed=1")

      assert conn.assigns[:embed_token]
      refute html_response(conn, 200) =~ @message
    end
  end

  defp count(html), do: length(String.split(html, @message)) - 1
end
