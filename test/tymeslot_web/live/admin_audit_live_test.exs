defmodule TymeslotWeb.AdminAuditLiveTest do
  @moduledoc """
  Audit tab of the admin hub: lists the security audit log, filters it, and
  is reachable by admins only.
  """

  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :security

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.AppSettingsEnvHelpers, only: [restore_app_settings_env: 1]
  import Tymeslot.Factory

  alias Tymeslot.AppSettings
  alias Tymeslot.Infrastructure.DashboardCache
  alias Tymeslot.Security.AuditLog
  alias Tymeslot.Security.AuditLog.AuditEventQueries
  alias Tymeslot.Security.SecurityLogger

  setup_all do
    case Process.whereis(DashboardCache) do
      nil -> start_supervised!(DashboardCache)
      _pid -> :ok
    end

    :ok
  end

  setup :restore_app_settings_env

  setup do
    original_router = Application.get_env(:tymeslot, :router)
    Application.put_env(:tymeslot, :router, TymeslotWeb.Router)
    Application.put_env(:tymeslot, :enable_admin_ui, true)
    DashboardCache.clear_all()

    on_exit(fn ->
      if original_router,
        do: Application.put_env(:tymeslot, :router, original_router),
        else: Application.delete_env(:tymeslot, :router)

      Application.put_env(:tymeslot, :enable_admin_ui, true)
    end)

    :ok
  end

  defp insert_admin do
    user = insert(:user, is_admin: true, onboarding_completed_at: DateTime.utc_now(:second))
    insert(:profile, user: user, username: "admin-#{user.id}")
    user
  end

  test "lists security events with the acting admin", %{conn: conn} do
    admin = insert_admin()
    target = insert(:user, email: "target@example.com")

    SecurityLogger.log_security_event("account_disabled", %{
      user_id: target.id,
      actor_user_id: admin.id
    })

    {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    assert html =~ "Audit log"
    assert html =~ "account_disabled"
    assert html =~ "target@example.com"
    assert html =~ admin.email
  end

  test "filters by event type and by user", %{conn: conn} do
    admin = insert_admin()
    alice = insert(:user, email: "alice@example.com")
    bob = insert(:user, email: "bob@example.com")

    SecurityLogger.log_security_event("password_change", %{user_id: alice.id})
    SecurityLogger.log_security_event("csrf_violation", %{user_id: bob.id})

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    html =
      lv
      |> form("#admin-audit-filter-form", audit: %{event_type: "csrf_violation"})
      |> render_change()

    assert html =~ "bob@example.com"
    refute html =~ "alice@example.com"

    html =
      lv
      |> form("#admin-audit-filter-form", audit: %{event_type: "", user: "alice"})
      |> render_change()

    assert html =~ "alice@example.com"
    refute html =~ "bob@example.com"
  end

  test "offers known event types before any was logged, and filters by category", %{
    conn: conn
  } do
    admin = insert_admin()
    SecurityLogger.log_security_event("session_created", %{user_id: admin.id})
    SecurityLogger.log_security_event("csrf_violation", %{user_id: admin.id})

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    assert has_element?(lv, ~s(#admin-audit-event-type option[value="admin_demoted"]))
    assert has_element?(lv, ~s(#admin-audit-event-type option[value="category:session"]))

    lv
    |> form("#admin-audit-filter-form", audit: %{event_type: "category:session"})
    |> render_change()

    assert has_element?(lv, "[data-testid='audit-event-row']", "session_created")
    refute has_element?(lv, "[data-testid='audit-event-row']", "csrf_violation")
  end

  test "pages through events 20 at a time and switches the page size", %{conn: conn} do
    admin = insert_admin()

    for _n <- 1..45 do
      {:ok, _event} = AuditEventQueries.insert(%{event_type: "password_change"})
    end

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    # Signing the admin in is audited too; count only the events made here.
    html =
      lv
      |> form("#admin-audit-filter-form", audit: %{event_type: "password_change"})
      |> render_change()

    assert html =~ "1–20 of 45"
    assert row_count(html) == 20

    html = lv |> element("#admin-audit-pagination button", "3") |> render_click()

    assert html =~ "41–45 of 45"
    assert row_count(html) == 5

    html =
      lv
      |> form("#admin-audit-pagination-per-page-form", audit_paging: %{per_page: "50"})
      |> render_change()

    assert html =~ "1–45 of 45"
    assert row_count(html) == 45
    refute has_element?(lv, "#admin-audit-pagination nav")
  end

  defp row_count(html) do
    html |> Floki.parse_document!() |> Floki.find("[data-testid='audit-event-row']") |> length()
  end

  test "filters by date range", %{conn: conn} do
    admin = insert_admin()
    SecurityLogger.log_security_event("password_change", %{user_id: admin.id})
    today = Date.utc_today()

    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    html =
      lv
      |> form("#admin-audit-filter-form",
        audit: %{from: Date.to_iso8601(today), to: Date.to_iso8601(today)}
      )
      |> render_change()

    assert html =~ "password_change"

    html =
      lv
      |> form("#admin-audit-filter-form",
        audit: %{from: Date.to_iso8601(Date.add(today, 1)), to: ""}
      )
      |> render_change()

    assert html =~ "No events match these filters."
  end

  test "shows a deleted user by id", %{conn: conn} do
    admin = insert_admin()

    SecurityLogger.log_security_event("account_deletion_success", %{
      user_id: 987_654,
      email: "gone@example.com"
    })

    {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    assert html =~ "#987654 (deleted) gone@example.com"
  end

  test "shows the full email of a sign-in attempt on an unknown account", %{conn: conn} do
    admin = insert_admin()

    SecurityLogger.log_authentication_attempt("Nobody.Here@example.com", false, "no_user", %{
      ip_address: "203.0.113.9"
    })

    {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    assert html =~ "nobody.here@example.com"
  end

  test "shows the masked email of an event recorded before full emails were kept", %{
    conn: conn
  } do
    admin = insert_admin()

    {:ok, _event} =
      AuditEventQueries.insert(%{
        event_type: "authentication_failure",
        email_masked: "o***@example.com"
      })

    {:ok, _lv, html} = live(log_in_user(conn, admin), ~p"/dashboard/admin/audit")

    assert html =~ "o***@example.com"
  end

  test "App Settings has an Audit log tab with retention and per-category switches", %{
    conn: conn
  } do
    admin = insert_admin()
    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin")

    html =
      lv
      |> element("button[phx-click='switch_settings_tab'][phx-value-option='audit_log']")
      |> render_click()

    assert html =~ "Keep audit events for"
    assert has_element?(lv, "#setting-input-audit_log_retention_days")
    assert has_element?(lv, "#admin-audit-event-row-session")
    assert has_element?(lv, "#admin-audit-event-row-honeypot")

    lv
    |> element(
      "#admin-audit-event-row-session button[phx-click='set_audit_event'][phx-value-state='false']"
    )
    |> render_click()

    refute AuditLog.recorded?("session_created")
    assert AppSettings.get(:audit_log_events) == %{"session" => false}
  end

  test "is not reachable by a non-admin", %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now(:second))
    insert(:profile, user: user)

    assert {:error, {_kind, %{to: "/dashboard"}}} =
             live(log_in_user(conn, user), ~p"/dashboard/admin/audit")
  end
end
