defmodule TymeslotWeb.AdminLiveBotProtectionTest do
  @moduledoc """
  Coverage for the admin settings "Bot protection" section's Off/Google/
  Cloudflare provider selector and the min-score row's visibility. Split out
  of `TymeslotWeb.AdminLiveTest` to stay under the project's per-module line
  count budget, same reasoning as `TymeslotWeb.AdminLiveEmailBrandingTest`.
  """

  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :security

  import Phoenix.LiveViewTest
  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers

  alias Tymeslot.AppSettings
  alias Tymeslot.Infrastructure.DashboardCache

  setup_all do
    case Process.whereis(DashboardCache) do
      nil -> start_supervised!(DashboardCache)
      _pid -> :ok
    end

    :ok
  end

  setup %{conn: conn} do
    original_router = Application.get_env(:tymeslot, :router)
    Application.put_env(:tymeslot, :router, TymeslotWeb.Router)
    Application.put_env(:tymeslot, :enable_admin_ui, true)
    Application.put_env(:tymeslot, :registration_enabled, true)
    DashboardCache.clear_all()

    # `AppSettings.update/1` writes through to `Application.put_env/3`
    # (`Env.flush_overrides/1`), which — unlike the Ecto sandbox — is not
    # rolled back between tests, so each test here must restore the config
    # (and the DB row) it changes.
    original_recaptcha = Application.get_env(:tymeslot, :recaptcha, [])

    on_exit(fn ->
      if original_router,
        do: Application.put_env(:tymeslot, :router, original_router),
        else: Application.delete_env(:tymeslot, :router)

      Application.put_env(:tymeslot, :enable_admin_ui, true)
      Application.put_env(:tymeslot, :registration_enabled, true)
      Application.put_env(:tymeslot, :recaptcha, original_recaptcha)
    end)

    admin =
      insert(:user, is_admin: true, onboarding_completed_at: DateTime.utc_now(:second))

    insert(:profile, user: admin, username: "admin-#{admin.id}")

    {:ok, conn: log_in_user(conn, admin), admin: admin}
  end

  test "the bot-protection provider selector offers Off/Google/Cloudflare and switches provider",
       %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
    html = switch_tab(lv, "authentication")

    # Defaults to Off in tests (config/test.exs).
    assert html =~
             ~s(phx-value-key="recaptcha_signup_provider" phx-value-state="off" disabled)

    lv |> setting_tag(:recaptcha_signup_provider, "google") |> render_click()

    assert Keyword.get(Application.get_env(:tymeslot, :recaptcha), :signup_provider) ==
             :google

    assert %{recaptcha_signup_provider: :google} = AppSettings.get!()
    assert flash_html(lv) =~ "Bot protection on signup set to Google."

    lv |> setting_tag(:recaptcha_signup_provider, "cloudflare") |> render_click()

    assert Keyword.get(Application.get_env(:tymeslot, :recaptcha), :signup_provider) ==
             :cloudflare
  end

  test "the signup min-score row only renders while Google is the signup provider",
       %{conn: conn} do
    {:ok, _settings} = AppSettings.update(%{recaptcha_signup_provider: :off})
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
    refute switch_tab(lv, "authentication") =~ "Signup min score"

    {:ok, _settings} = AppSettings.update(%{recaptcha_signup_provider: :cloudflare})
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
    refute switch_tab(lv, "authentication") =~ "Signup min score"

    {:ok, _settings} = AppSettings.update(%{recaptcha_signup_provider: :google})
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
    assert switch_tab(lv, "authentication") =~ "Signup min score"
  end

  defp setting_tag(lv, key, state) do
    element(
      lv,
      ~s|button[phx-click="set_setting"][phx-value-key="#{key}"][phx-value-state="#{state}"]|
    )
  end

  defp switch_tab(lv, tab) do
    lv |> with_target("#admin-hub") |> render_click("switch_settings_tab", %{"option" => tab})
  end

  # `HubComponent` forwards flash messages to `DashboardLive` via
  # `TymeslotWeb.Live.Shared.Flash` — `send/2` plus a `handle_info/2` cycle,
  # since a bare `put_flash/3` on a component's own socket is silently
  # dropped. That cycle runs after the triggering `render_click`/`render_submit`
  # call already returned, so drain the mailbox before reading the flash back.
  defp flash_html(lv) do
    :sys.get_state(lv.pid)
    render(lv)
  end
end
