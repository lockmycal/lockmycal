defmodule Tymeslot.AdminPageHelpers do
  @moduledoc """
  Shared `setup` for LiveView tests that drive the admin pages.

  Reaching the admin hub in a test needs three things arranged together: the
  endpoint pointed at Core's router, the admin UI switched on, and a signed-in
  admin. Under a downstream overlay the endpoint routes through that overlay's
  router by default, which 404s Core's admin scope — these tests cover Core
  behaviour, not an overlay's lockdown, which has its own coverage.

  The admin hub mounts through the regular dashboard hook chain (it's
  `DashboardLive` under `:admin`/`:admin_users`, not a standalone LiveView),
  so an admin actor needs onboarding marked complete or `DashboardInitHook`
  redirects to `/onboarding` before the admin check ever runs — hence the
  profile alongside the user, same as `AdminLiveTest.insert_admin/1`.

  Extracted so the admin test modules share one copy rather than each carrying
  the same block.
  """

  use TymeslotWeb, :verified_routes

  import ExUnit.Callbacks, only: [on_exit: 1]
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest, only: [live: 2, render_click: 3, with_target: 2]
  import Tymeslot.AuthTestHelpers, only: [log_in_user: 2]
  import Tymeslot.Factory, only: [insert: 2]

  @endpoint TymeslotWeb.Endpoint

  @doc """
  ExUnit `setup` callback returning a `conn` signed in as an admin, with the
  router and admin-UI flag restored afterwards. Use as
  `setup :admin_conn`.
  """
  @spec admin_conn(map()) :: {:ok, keyword()}
  def admin_conn(%{conn: conn}) do
    original_router = Application.get_env(:tymeslot, :router)
    Application.put_env(:tymeslot, :router, TymeslotWeb.Router)
    Application.put_env(:tymeslot, :enable_admin_ui, true)

    on_exit(fn ->
      if original_router,
        do: Application.put_env(:tymeslot, :router, original_router),
        else: Application.delete_env(:tymeslot, :router)

      Application.put_env(:tymeslot, :enable_admin_ui, true)
    end)

    admin = insert(:user, is_admin: true, onboarding_completed_at: DateTime.utc_now(:second))
    insert(:profile, user: admin, username: "admin-#{admin.id}")

    {:ok, conn: log_in_user(conn, admin), admin: admin}
  end

  @doc """
  Mounts the admin hub and switches to one of the Settings sub-tabs
  (`:authentication`, `:email`, or `:general`) before returning — since
  `HubComponent.handle_event("switch_settings_tab", ...)`, which of the three
  is showing lives in the component's own state, not a route (there is no
  `/admin/<tab>` URL any more).
  """
  @spec live_admin_settings_tab(Plug.Conn.t(), atom() | String.t()) ::
          {:ok, Phoenix.LiveViewTest.View.t(), String.t()}
  def live_admin_settings_tab(conn, tab) do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

    html =
      lv
      |> with_target("#admin-hub")
      |> render_click("switch_settings_tab", %{"option" => to_string(tab)})

    {:ok, lv, html}
  end
end
