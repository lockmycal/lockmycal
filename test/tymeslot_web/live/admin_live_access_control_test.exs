defmodule TymeslotWeb.AdminLiveAccessControlTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :auth

  import Phoenix.LiveViewTest
  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers

  alias Phoenix.Flash
  alias Tymeslot.Auth
  alias Tymeslot.Infrastructure.DashboardCache

  setup_all do
    case Process.whereis(DashboardCache) do
      nil -> start_supervised!(DashboardCache)
      _pid -> :ok
    end

    :ok
  end

  setup do
    # Under a downstream overlay, the endpoint routes through that overlay's
    # router by default. Point it at Core's router so the admin hub is
    # reachable for these tests: they cover Core behaviour, not an overlay's
    # lockdown, which has its own coverage.
    original_router = Application.get_env(:tymeslot, :router)
    Application.put_env(:tymeslot, :router, TymeslotWeb.Router)
    Application.put_env(:tymeslot, :enable_admin_ui, true)
    Application.put_env(:tymeslot, :registration_enabled, true)
    DashboardCache.clear_all()

    on_exit(fn ->
      if original_router,
        do: Application.put_env(:tymeslot, :router, original_router),
        else: Application.delete_env(:tymeslot, :router)

      Application.put_env(:tymeslot, :enable_admin_ui, true)
      Application.put_env(:tymeslot, :registration_enabled, true)
    end)

    :ok
  end

  # The admin hub now mounts through the regular dashboard hook chain (it's
  # `DashboardLive` under `:admin`/`:admin_users`, not a standalone LiveView),
  # so — unlike the old standalone `/admin` — an admin actor needs onboarding
  # marked complete or `DashboardInitHook` redirects to `/onboarding` before
  # `handle_params/3` (and its admin check) ever runs. A profile keeps the
  # rest of the dashboard chrome (sidebar, user dropdown) rendering
  # realistically.
  defp insert_admin(attrs \\ []) do
    user =
      insert(
        :user,
        Keyword.merge(
          [is_admin: true, onboarding_completed_at: DateTime.utc_now(:second)],
          attrs
        )
      )

    insert(:profile, user: user, username: "admin-#{user.id}")
    user
  end

  describe "access control" do
    test "authenticated non-admin is redirected to /dashboard with a flash", %{conn: conn} do
      user = insert(:user, is_admin: false, onboarding_completed_at: DateTime.utc_now(:second))
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/dashboard/admin")
      assert redirected_to(conn) == ~p"/dashboard"
      assert Flash.get(conn.assigns.flash, :error) == "Admin access required."
    end

    test "unauthenticated request redirected to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: redirect_to}}} = live(conn, ~p"/dashboard/admin")
      assert redirect_to =~ "/auth/login"
    end

    test "admin user can mount the admin hub and lands on the general tab", %{conn: conn} do
      conn = log_in_user(conn, insert_admin())

      {:ok, _lv, html} = live(conn, ~p"/dashboard/admin")
      assert html =~ "Admin"
      # The first tab's own sections, not another tab's.
      assert html =~ "Payments"
      assert html =~ "Booking analytics"
      refute html =~ "Password authentication"
    end

    test "admin UI disabled redirects even an admin to /dashboard with a flash", %{conn: conn} do
      Application.put_env(:tymeslot, :enable_admin_ui, false)
      conn = log_in_user(conn, insert_admin())

      conn = get(conn, ~p"/dashboard/admin")
      assert redirected_to(conn) == ~p"/dashboard"
      assert Flash.get(conn.assigns.flash, :error) == "Admin access required."
    end

    test "the sidebar link patches into the hub without leaving the dashboard view",
         %{conn: conn} do
      conn = log_in_user(conn, insert_admin())

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      assert has_element?(lv, "aside#dashboard-sidebar")

      html = lv |> element(~s|a[href="/dashboard/admin"]|) |> render_click()

      # Same LiveView process (a `patch`, not a `navigate`): the hub's content
      # swapped in, but the surrounding dashboard chrome never tore down.
      assert html =~ "Payments"
      assert has_element?(lv, "aside#dashboard-sidebar")
    end

    test "App Settings and Users patch into the same persistent component, not a remount", %{
      conn: conn
    } do
      conn = log_in_user(conn, insert_admin())

      {:ok, lv, html} = live(conn, ~p"/dashboard/admin")
      cid = admin_hub_cid(html)

      # `ComponentDispatch.component_id/1` gives both admin actions the same
      # id, so this is the same `HubComponent` instance throughout — not one
      # unmounted and remounted on every patch (a real-browser client-side
      # rendering bug when the two actions used distinct ids).
      html = lv |> element(~s|a[href="/dashboard/admin/users"]|) |> render_click()
      assert admin_hub_cid(html) == cid
      assert html =~ "Total users"

      html = lv |> element(~s|a[href="/dashboard/admin"]|) |> render_click()
      assert admin_hub_cid(html) == cid
      assert html =~ "Payments"
    end

    test "navigating away from Users clears a pending promote confirmation", %{conn: conn} do
      admin = insert_admin()
      target = insert(:user, is_admin: false)
      conn = log_in_user(conn, admin)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")
      html = lv |> promote_button(target.id) |> render_click()
      assert html =~ "Promote user to admin"

      lv |> element(~s|a[href="/dashboard/admin"]|) |> render_click()
      html = lv |> element(~s|a[href="/dashboard/admin/users"]|) |> render_click()

      refute html =~ "Promote user to admin"
    end

    test "open socket is redirected to /dashboard after actor's admin status is revoked", %{
      conn: conn
    } do
      admin_a = insert_admin()
      admin_b = insert_admin()
      target = insert(:user, is_admin: false)
      conn = log_in_user(conn, admin_a)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      # Revoke admin_a's admin status via another admin (admin_b acting as the actor)
      {:ok, _demoted} = Auth.demote_admin(admin_b, admin_a.id)

      # Sending any event through the now-demoted socket must be halted and redirected
      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               lv |> promote_button(target.id) |> render_click()

      assert redirect_to =~ "/dashboard"
    end

    test "patching between tabs is halted after the actor's admin status is revoked", %{
      conn: conn
    } do
      admin_a = insert_admin()
      admin_b = insert_admin()
      conn = log_in_user(conn, admin_a)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      # Revoke admin_a while their socket is still open.
      {:ok, _demoted} = Auth.demote_admin(admin_b, admin_a.id)

      # A patch to the users tab runs handle_params → the admin check there,
      # which must halt before the hub component re-queries admin-only data.
      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               render_patch(lv, ~p"/dashboard/admin/users")

      assert redirect_to =~ "/dashboard"
    end
  end

  defp promote_button(lv, id) do
    element(lv, ~s|button[phx-click="request_promote"][phx-value-id="#{id}"]|)
  end

  # The numeric `data-phx-component` id LiveView stamps on the hub's root
  # element — same value across a patch means it's still the same component
  # process, not a fresh mount.
  defp admin_hub_cid(html) do
    Enum.at(Regex.run(~r/data-phx-component="(\d+)" id="admin-hub"/, html), 1)
  end
end
