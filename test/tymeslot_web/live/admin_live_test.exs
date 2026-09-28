defmodule TymeslotWeb.AdminLiveTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :auth

  import Phoenix.LiveViewTest
  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers

  alias Phoenix.Flash
  alias Tymeslot.Analytics
  alias Tymeslot.AppSettings
  alias Tymeslot.Auth
  alias Tymeslot.Infrastructure.DashboardCache
  alias TymeslotWeb.Helpers.ClientIP

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

  describe "settings tab" do
    setup %{conn: conn} do
      admin = insert_admin()
      {:ok, conn: log_in_user(conn, admin), admin: admin}
    end

    test "clicking the Disabled tag persists and takes effect immediately", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      switch_tab(lv, "authentication")

      lv |> setting_tag(:registration_enabled, "false") |> render_click()

      assert Application.get_env(:tymeslot, :registration_enabled) == false
      assert %{registration_enabled: false} = AppSettings.get!()
      assert flash_html(lv) =~ "Registration enabled disabled."
    end

    test "clicking the Enabled tag persists and takes effect immediately", %{conn: conn} do
      AppSettings.load!()
      {:ok, _settings} = AppSettings.update(%{registration_enabled: false})

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      switch_tab(lv, "authentication")

      lv |> setting_tag(:registration_enabled, "true") |> render_click()

      assert Application.get_env(:tymeslot, :registration_enabled) == true
      assert %{registration_enabled: true} = AppSettings.get!()
      assert flash_html(lv) =~ "Registration enabled enabled."
    end

    test "toggling booking analytics persists and flips Analytics.enabled?/0", %{conn: conn} do
      on_exit(fn -> Application.put_env(:tymeslot, :booking_analytics_enabled, true) end)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      switch_tab(lv, "general")

      lv |> setting_tag(:booking_analytics_enabled, "false") |> render_click()

      assert Application.get_env(:tymeslot, :booking_analytics_enabled) == false
      assert %{booking_analytics_enabled: false} = AppSettings.get!()
      refute Analytics.enabled?()
      assert flash_html(lv) =~ "Booking analytics disabled."
    end

    test "the tag matching the effective value is disabled so re-clicks are no-ops", %{conn: conn} do
      AppSettings.load!()
      {:ok, _settings} = AppSettings.update(%{registration_enabled: false})

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "authentication")

      # The Disabled tag is active because the effective value is false.
      assert html =~
               ~s(phx-value-key="registration_enabled" phx-value-state="false" disabled)
    end

    test "row-level dimming only applies when a setting genuinely cannot be activated",
         %{conn: conn} do
      # Off, but freely togglable — must not look inactive.
      {:ok, _settings} = AppSettings.update(%{registration_enabled: false})
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "authentication")
      refute dimmed_row?(html, :registration_enabled)

      # admin_alert_email lives on the "email" tab, gated by a disabled parent
      # (admin_alerts_enabled defaults to false).
      html = switch_tab(lv, "email")
      assert dimmed_row?(html, :admin_alert_email)

      # meeting_payments_enabled lives on the "general" tab. Locked off with
      # no Stripe platform key (default test fixture)...
      Application.put_env(:stripity_stripe, :api_key, "sk_test_fake")
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "general")
      assert dimmed_row?(html, :meeting_payments_enabled)
      assert html =~ ~s(phx-value-key="meeting_payments_enabled" phx-value-state="true" disabled)

      # ...and no longer once a real key is configured.
      Application.put_env(:stripity_stripe, :api_key, "sk_test_51Hxxxxxxxxxxxxxxxxxxxxxx")
      on_exit(fn -> Application.put_env(:stripity_stripe, :api_key, "sk_test_fake") end)
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "general")
      refute dimmed_row?(html, :meeting_payments_enabled)
    end

    test "each setting row shows a description with a recommended value", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "authentication")

      assert html =~ "Allow new users to sign up"
      assert html =~ "Allow log-in with email and password"
      assert html =~ "Recommended: Enabled"
    end

    test "shows an info banner explaining the env-var override behaviour", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard/admin")

      assert html =~ "override the matching environment variables"
      assert html =~ "REGISTRATION_ENABLED"
      assert html =~ "PASSWORD_AUTH_ENABLED"
    end

    test "toggling registration off via the LiveView blocks public sign-ups", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      switch_tab(lv, "authentication")

      lv |> setting_tag(:registration_enabled, "false") |> render_click()

      # End-to-end: an admin's click in the UI propagates through to the
      # public registration entry point.
      assert {:error, :registration_disabled, _msg} =
               Auth.register_user(
                 %{"email" => "new@example.com"},
                 ClientIP.request_opts(%Plug.Conn{})
               )

      lv |> setting_tag(:registration_enabled, "true") |> render_click()

      refute match?(
               {:error, :registration_disabled, _ignored},
               Auth.register_user(
                 %{"email" => "new@example.com"},
                 ClientIP.request_opts(%Plug.Conn{})
               )
             )
    end

    test "Disabled tag for password auth is locked when an admin uses password auth",
         %{conn: conn} do
      # The setup admin has a password_hash, so disabling password auth would
      # lock them out. The toggle should be rendered as disabled upfront —
      # never relying on the after-click flash to communicate the block.
      # Force SSO off so the lockout guard isn't satisfied by a parallel auth
      # path — shell env (ENABLE_GOOGLE_AUTH etc.) can otherwise enable it.
      with_sso_disabled()

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "authentication")

      assert html =~
               ~s(phx-value-key="password_auth_enabled" phx-value-state="false" disabled)

      assert html =~ "Cannot disable password authentication"
    end

    test "bot-protection provider descriptions mention both providers' key requirements",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "authentication")

      assert html =~ "RECAPTCHA_SITE_KEY"
      assert html =~ "RECAPTCHA_SECRET_KEY"
      assert html =~ "TURNSTILE_SITE_KEY"
      assert html =~ "TURNSTILE_SECRET_KEY"
    end

    test "submitting a valid score persists the value and takes effect immediately",
         %{conn: conn} do
      original_recaptcha = Application.get_env(:tymeslot, :recaptcha) || []
      on_exit(fn -> Application.put_env(:tymeslot, :recaptcha, original_recaptcha) end)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_submit("save_setting", %{
        "key" => "recaptcha_signup_min_score",
        "value" => "0.7"
      })

      assert flash_html(lv) =~ "Signup min score updated."

      assert Keyword.get(Application.get_env(:tymeslot, :recaptcha), :signup_min_score) ==
               0.7
    end

    test "submitting an out-of-range score surfaces an inline error",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_submit("save_setting", %{
        "key" => "recaptcha_booking_min_score",
        "value" => "2.0"
      })

      assert flash_html(lv) =~ "between 0.0 and 1.0"
    end

    test "changing a valid upload size setting persists without a Save button — it autosaves on blur, like the score fields",
         %{conn: conn} do
      {:ok, _settings} = AppSettings.reset(:max_image_upload_size_mb)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      # max_image_upload_size_mb lives under the "Uploads" section, which is
      # on the "general" tab, not the "authentication" tab shown at mount.
      html = switch_tab(lv, "general")

      # Same shape as the score fields — phx-change autosaves on blur and
      # there is no visible Save button. Every other text/email/colour
      # setting on this page follows the same pattern; see the "admin alert
      # email" test below for that kind.
      [form_html] =
        Regex.run(~r{<form id="admin-setting-form-max_image_upload_size_mb".*?</form>}s, html)

      assert form_html =~ ~s(phx-change="save_setting")
      refute form_html =~ ~s(type="submit")

      lv
      |> with_target("#admin-hub")
      |> render_change("save_setting", %{
        "key" => "max_image_upload_size_mb",
        "value" => "42"
      })

      assert flash_html(lv) =~ "Max background image size updated."
      assert Keyword.get(Application.get_env(:tymeslot, :uploads), :max_image_size_mb) == 42
    end

    test "changing an out-of-range upload size setting surfaces an inline error",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_change("save_setting", %{
        "key" => "max_video_upload_size_mb",
        "value" => "0"
      })

      assert flash_html(lv) =~ "whole number of megabytes"
    end

    test "submitting a valid admin alert email persists the value",
         %{conn: conn} do
      original_admin_alert_email = Application.get_env(:tymeslot, :admin_alert_email)

      on_exit(fn ->
        if original_admin_alert_email == nil do
          Application.delete_env(:tymeslot, :admin_alert_email)
        else
          Application.put_env(:tymeslot, :admin_alert_email, original_admin_alert_email)
        end
      end)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_submit("save_setting", %{
        "key" => "admin_alert_email",
        "value" => "ops@example.com"
      })

      assert flash_html(lv) =~ "Admin alert recipient updated."
      assert Application.get_env(:tymeslot, :admin_alert_email) == "ops@example.com"
    end

    test "changing the admin alert email persists without a Save button — it autosaves on blur",
         %{conn: conn} do
      original_admin_alert_email = Application.get_env(:tymeslot, :admin_alert_email)

      on_exit(fn ->
        if original_admin_alert_email == nil do
          Application.delete_env(:tymeslot, :admin_alert_email)
        else
          Application.put_env(:tymeslot, :admin_alert_email, original_admin_alert_email)
        end
      end)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      html = switch_tab(lv, "email")

      [form_html] =
        Regex.run(~r{<form id="admin-setting-form-admin_alert_email".*?</form>}s, html)

      assert form_html =~ ~s(phx-change="save_setting")
      refute form_html =~ ~s(type="submit")

      lv
      |> with_target("#admin-hub")
      |> render_change("save_setting", %{
        "key" => "admin_alert_email",
        "value" => "ops@example.com"
      })

      assert flash_html(lv) =~ "Admin alert recipient updated."
      assert Application.get_env(:tymeslot, :admin_alert_email) == "ops@example.com"
    end

    test "submitting a malformed admin alert email surfaces an inline error",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_submit("save_setting", %{
        "key" => "admin_alert_email",
        "value" => "not-an-email"
      })

      assert flash_html(lv) =~ "valid email address"
    end

    test "submitting a blank admin alert email clears the override",
         %{conn: conn} do
      {:ok, _settings} = AppSettings.update(%{admin_alert_email: "ops@example.com"})

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_submit("save_setting", %{"key" => "admin_alert_email", "value" => ""})

      assert %{admin_alert_email: nil} = AppSettings.get!()
    end

    test "toggling google_auth_enabled flows into the social_auth keyword list",
         %{conn: conn} do
      # Force a known starting state — shell env (ENABLE_GOOGLE_AUTH) can
      # otherwise enable the toggle at boot, making the "Enabled" button
      # render as disabled (since it matches the effective value).
      original_social_auth = Application.get_env(:tymeslot, :social_auth) || []
      on_exit(fn -> Application.put_env(:tymeslot, :social_auth, original_social_auth) end)

      Application.put_env(
        :tymeslot,
        :social_auth,
        Keyword.put(original_social_auth, :google_enabled, false)
      )

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      switch_tab(lv, "authentication")

      lv |> setting_tag(:google_auth_enabled, "true") |> render_click()

      assert Keyword.get(Application.get_env(:tymeslot, :social_auth), :google_enabled) == true
      assert %{google_auth_enabled: true} = AppSettings.get!()
    end

    test "stale set_setting event surfaces the lockout reason as a flash",
         %{conn: conn} do
      # In steady state the Disabled tag is rendered with `disabled`, so a real
      # browser can't fire this event. The server-side guard still has to hold
      # for the race where the lockout state changes between page render and
      # click — exercise it by firing the event directly at the hub component,
      # bypassing the DOM's disabled attribute (`with_target` emulates
      # `phx-target` without dispatching through an actual element).
      with_sso_disabled()
      original_password_auth = Application.get_env(:tymeslot, :password_auth_enabled)

      on_exit(fn ->
        if original_password_auth == nil do
          Application.delete_env(:tymeslot, :password_auth_enabled)
        else
          Application.put_env(:tymeslot, :password_auth_enabled, original_password_auth)
        end
      end)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_click("set_setting", %{"key" => "password_auth_enabled", "state" => "false"})

      assert flash_html(lv) =~ "at least one admin signs in with email and password"
      # The setting did not actually change.
      assert Application.get_env(:tymeslot, :password_auth_enabled) == true
    end

    test "rejecting an SSO toggle surfaces the SSO lock reason, not the password one",
         %{conn: conn} do
      # Credentialed OIDC is the only usable path (password auth off), so
      # disabling it would lock everyone out. The rejection flash must use the
      # SSO-specific copy rather than the hardcoded password-auth message.
      original_social_auth = Application.get_env(:tymeslot, :social_auth)
      original_oauth = Application.get_env(:tymeslot, :oauth_provider)
      original_password = Application.get_env(:tymeslot, :password_auth_enabled)

      on_exit(fn ->
        restore_env(:social_auth, original_social_auth)
        restore_env(:oauth_provider, original_oauth)
        restore_env(:password_auth_enabled, original_password)
      end)

      Application.put_env(:tymeslot, :social_auth,
        google_enabled: false,
        github_enabled: false,
        oauth_enabled: true
      )

      Application.put_env(:tymeslot, :oauth_provider,
        client_id: "oidc-id",
        client_secret: "oidc-secret"
      )

      Application.put_env(:tymeslot, :password_auth_enabled, false)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_click("set_setting", %{"key" => "oauth_auth_enabled", "state" => "false"})

      drain(lv)

      # Scope the assertions to the flash itself: the static page always carries
      # the phrase "email and password" in the password-auth toggle description
      # and lock title, so only the flash region distinguishes which lock reason
      # was surfaced.
      flash = lv |> element("#app-flash-group-error") |> render()

      assert flash =~ "only working sign-in path"
      refute flash =~ "email and password"
      # The toggle did not change.
      assert Keyword.get(Application.get_env(:tymeslot, :social_auth), :oauth_enabled) == true
    end
  end

  # The Users tab lives in TymeslotWeb.AdminUsersLiveTest (kept separate so
  # each test module stays under the line-count limit).

  defp promote_button(lv, id) do
    element(lv, ~s|button[phx-click="request_promote"][phx-value-id="#{id}"]|)
  end

  # The numeric `data-phx-component` id LiveView stamps on the hub's root
  # element — same value across a patch means it's still the same component
  # process, not a fresh mount.
  defp admin_hub_cid(html) do
    Enum.at(Regex.run(~r/data-phx-component="(\d+)" id="admin-hub"/, html), 1)
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

  defp restore_env(key, nil), do: Application.delete_env(:tymeslot, key)
  defp restore_env(key, value), do: Application.put_env(:tymeslot, key, value)

  # `HubComponent` forwards flash messages to DashboardLive via
  # `TymeslotWeb.Live.Shared.Flash` — `send/2` plus a `handle_info/2` cycle,
  # since a bare `put_flash/3` on a component's own socket is silently
  # dropped. That cycle runs after the triggering `render_click`/`render_submit`
  # call already returned, so callers must drain the mailbox before reading
  # the flash back out (see `TymeslotWeb.Dashboard.ThemeSettingsFlashTest`
  # for the same pattern elsewhere in this codebase).
  defp drain(lv), do: :sys.get_state(lv.pid)

  defp flash_html(lv) do
    drain(lv)
    render(lv)
  end

  # True when `key`'s *control* (not its description, which may legitimately
  # mute itself — see AdminLiveSettingRowTest) is genuinely inert via
  # `parent_disabled?/2`. A locked `setting_tag` pill carries `aria-disabled=""`
  # (set only from `@locked`, unlike `disabled`, which is *also* true for
  # whichever pill merely reflects the current value); a disabled text/email
  # input has no such pill and carries `disabled=""` directly on its own id.
  defp dimmed_row?(html, key) do
    {row_start, _len} = :binary.match(html, ~s(id="admin-setting-row-#{key}"))
    row = binary_part(html, row_start, byte_size(html) - row_start)

    {control_start, _len} = :binary.match(row, "aria-label=\"Set ")
    control = binary_part(row, control_start, min(1000, byte_size(row) - control_start))

    control =~ ~s(aria-disabled="") or
      Regex.match?(~r/id="setting-input-#{key}"[^>]*\sdisabled=""/, control)
  end

  # Forces `:social_auth` to all-disabled and restores the original on exit.
  # Without this, shell vars like `ENABLE_GOOGLE_AUTH=true` leak through
  # runtime.exs into the test BEAM and confuse the "no usable auth path"
  # lockout guard, which considers any enabled SSO provider a valid fallback.
  defp with_sso_disabled do
    original = Application.get_env(:tymeslot, :social_auth, [])
    on_exit(fn -> Application.put_env(:tymeslot, :social_auth, original) end)

    Application.put_env(:tymeslot, :social_auth,
      google_enabled: false,
      github_enabled: false,
      oauth_enabled: false
    )
  end
end
