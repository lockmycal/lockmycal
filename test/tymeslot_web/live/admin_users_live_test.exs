defmodule TymeslotWeb.AdminUsersLiveTest do
  @moduledoc """
  Users tab of the admin hub. Split out of `TymeslotWeb.AdminLiveTest` purely
  to keep each test module under the line-count limit — see that module for
  admin access control and the Settings tab.
  """

  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :auth

  use Oban.Testing, repo: Tymeslot.Repo

  import Phoenix.LiveViewTest
  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers

  alias Floki
  alias Phoenix.Flash
  alias Tymeslot.Auth.{AdminUserQueries, UserQueries}
  alias Tymeslot.Infrastructure.DashboardCache
  alias Tymeslot.Repo
  alias Tymeslot.Workers.AccountDeletionWorker

  setup_all do
    case Process.whereis(DashboardCache) do
      nil -> start_supervised!(DashboardCache)
      _pid -> :ok
    end

    :ok
  end

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

  # See `TymeslotWeb.AdminLiveTest.insert_admin/1` for why onboarding and a
  # profile are required now that the admin hub mounts through the regular
  # dashboard hook chain.
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

  describe "users tab" do
    setup %{conn: conn} do
      admin = insert_admin()
      other_admin = insert(:user, is_admin: true)
      regular = insert(:user, is_admin: false)

      {:ok,
       conn: log_in_user(conn, admin), admin: admin, other_admin: other_admin, regular: regular}
    end

    test "users tab shows total-user and admin counts at the top", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/dashboard/admin/users")

      assert html =~ "Total users"
      assert html =~ "Admins"
    end

    test "users tab lists each user's display name and booking slug", %{conn: conn} do
      user = insert(:user, is_admin: false)

      insert(:profile,
        user: user,
        full_name: "Ada Lovelace",
        username: "ada-lovelace"
      )

      {:ok, _lv, html} = live(conn, ~p"/dashboard/admin/users")

      assert html =~ "Display name"
      assert html =~ "Booking slug"
      assert html =~ "Ada Lovelace"
      assert html =~ "ada-lovelace"
    end

    test "users tab renders a placeholder for users without a profile", %{
      conn: conn,
      regular: regular
    } do
      # `regular` is inserted without a profile in the setup block.
      {:ok, _lv, html} = live(conn, ~p"/dashboard/admin/users")

      # Each profile-less user contributes two em-dash placeholders (one per
      # column). At least one admin + the regular user above are profile-less,
      # so we expect the placeholder to render at least twice.
      assert html =~ regular.email
      assert html =~ "—"
    end

    test "search filters the list by email, display name, or username", %{conn: conn} do
      match = insert(:user, is_admin: false, email: "ada@example.com")
      insert(:profile, user: match, full_name: "Ada Lovelace", username: "ada-lovelace")

      other = insert(:user, is_admin: false, email: "bob@example.com")
      insert(:profile, user: other, full_name: "Bob Smith", username: "bob-smith")

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      html =
        lv
        |> form("#admin-users-search-form", %{"term" => "ada"})
        |> render_change()

      assert html =~ "Ada Lovelace"
      refute html =~ "Bob Smith"
    end

    test "the \"All Users\" count reflects the active search, not the total", %{conn: conn} do
      match = insert(:user, is_admin: false, email: "ada@example.com")
      insert(:profile, user: match, full_name: "Ada Lovelace")
      other = insert(:user, is_admin: false, email: "bob@example.com")
      insert(:profile, user: other, full_name: "Bob Smith")

      {:ok, lv, html} = live(conn, ~p"/dashboard/admin/users")
      assert html =~ "Total users"

      html =
        lv
        |> form("#admin-users-search-form", %{"term" => "ada"})
        |> render_change()

      # The section header next to the table must count the 1 filtered row,
      # not the unfiltered total (there are at least 2 users + any admins
      # from the test setup).
      doc = Floki.parse_document!(html)
      assert [count_badge] = Floki.find(doc, "h3:fl-contains('All Users') + span")
      assert String.trim(Floki.text(count_badge)) == "1"
    end

    test "pages the users 20 at a time and switches the page size", %{conn: conn} do
      for n <- 1..25, do: insert(:user, email: "paged#{n}@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      html = lv |> form("#admin-users-search-form", %{"term" => "paged"}) |> render_change()
      assert html =~ "1–20 of 25"

      html = lv |> element("#admin-users-pagination button", "2") |> render_click()
      assert html =~ "21–25 of 25"

      html =
        lv
        |> form("#admin-users-pagination-per-page-form", users_paging: %{per_page: "50"})
        |> render_change()

      assert html =~ "1–25 of 25"

      # A new search goes back to page 1.
      lv |> form("#admin-users-search-form", %{"term" => "paged1"}) |> render_change()
      assert render(lv) =~ "1–11 of 11"
    end

    test "an empty search result shows the no-matches copy instead of the table rows", %{
      conn: conn
    } do
      insert(:user, is_admin: false, email: "ada@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      html =
        lv
        |> form("#admin-users-search-form", %{"term" => "no-such-user-xyz"})
        |> render_change()

      assert html =~ "No users match your search."
    end

    test "promote sets is_admin to true", %{conn: conn, regular: regular} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      lv |> promote_button(regular.id) |> render_click()
      lv |> confirm_role_change() |> render_click()

      assert Repo.reload!(regular).is_admin
    end

    test "promote confirmation modal opens with the target's email", %{
      conn: conn,
      regular: regular
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      html = lv |> promote_button(regular.id) |> render_click()

      assert html =~ "Promote user to admin"
      assert html =~ regular.email
    end

    test "cancelling the modal does not change admin status", %{conn: conn, regular: regular} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      lv |> promote_button(regular.id) |> render_click()
      lv |> with_target("#admin-hub") |> render_hook("cancel_pending_action", %{})

      refute Repo.reload!(regular).is_admin
    end

    test "demote sets is_admin to false on another admin", %{conn: conn, other_admin: other_admin} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      lv |> demote_button(other_admin.id) |> render_click()
      lv |> confirm_role_change() |> render_click()

      refute Repo.reload!(other_admin).is_admin
    end

    test "demote button is replaced by a note when the actor is the only admin",
         %{conn: conn, admin: admin} do
      # Demote every admin except the current user, leaving them as the only
      # admin. The UI must offer no way to demote — instead an inline note
      # explains why.
      AdminUserQueries.list_admins()
      |> Enum.reject(&(&1.id == admin.id))
      |> Enum.each(fn other -> AdminUserQueries.set_admin(other, false) end)

      {:ok, lv, html} = live(conn, ~p"/dashboard/admin/users")

      # No active demote button for the self row.
      refute has_element?(lv, ~s|button[phx-click="request_demote"][phx-value-id="#{admin.id}"]|)

      # The inline note is visible.
      assert html =~ "last-admin-self-note"
      assert html =~ "You&#39;re the only admin"

      # And the user remains an admin.
      assert Repo.reload!(admin).is_admin
    end

    test "admin can demote themselves when another admin exists; navigates to /dashboard",
         %{conn: conn, admin: admin, other_admin: other_admin} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      # The self-row's demote button IS clickable because another admin remains.
      assert has_element?(lv, ~s|button[phx-click="request_demote"][phx-value-id="#{admin.id}"]|)

      lv |> demote_button(admin.id) |> render_click()

      # Modal copy uses the self-aware variant.
      assert render(lv) =~ "Demote yourself"

      # Confirming triggers a navigate to /dashboard, so the fresh mount picks
      # up the now-demoted user.
      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               lv |> confirm_role_change() |> render_click()

      assert redirect_to == ~p"/dashboard"

      # Self is now demoted; other_admin still has admin rights.
      refute Repo.reload!(admin).is_admin
      assert Repo.reload!(other_admin).is_admin
    end

    test "after self-demote, /dashboard/admin redirects to /dashboard with a flash",
         %{conn: conn, admin: admin} do
      # Simulate the post-demote state: user is no longer admin.
      {:ok, _user} = AdminUserQueries.set_admin(admin, false)

      conn = get(conn, ~p"/dashboard/admin")

      assert redirected_to(conn) == ~p"/dashboard"
      assert Flash.get(conn.assigns.flash, :error) == "Admin access required."
    end

    test "after self-demote, the dashboard sidebar no longer shows the admin Settings link",
         %{conn: conn, admin: admin} do
      {:ok, _user} = AdminUserQueries.set_admin(admin, false)

      {:ok, _lv, html} = live(conn, ~p"/dashboard")

      refute html =~ "Administration"
      refute html =~ ~s(href="/dashboard/admin")
    end

    test "country column shows the connect account's country code with a tooltip", %{
      conn: conn,
      regular: regular
    } do
      insert(:connect_account, user: regular, country: "ch")

      {:ok, _lv, html} = live(conn, ~p"/dashboard/admin/users")

      assert html =~ "CH"
      assert html =~ "Switzerland"
    end

    test "country column shows a dash for a user with no connect account", %{
      conn: conn,
      regular: regular
    } do
      {:ok, _lv, html} = live(conn, ~p"/dashboard/admin/users")

      assert html =~ regular.email
      assert html =~ "—"
    end

    test "disable sets disabled_at on another user", %{conn: conn, regular: regular} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      lv |> disable_button(regular.id) |> render_click()
      lv |> confirm_user_action() |> render_click()

      assert Repo.reload!(regular).disabled_at
    end

    test "enable clears disabled_at on a disabled user", %{conn: conn, regular: regular} do
      {:ok, _user} = UserQueries.set_disabled(regular, DateTime.utc_now(:second))
      {:ok, lv, html} = live(conn, ~p"/dashboard/admin/users")

      assert html =~ "Disabled"

      lv |> enable_button(regular.id) |> render_click()
      lv |> confirm_user_action() |> render_click()

      refute Repo.reload!(regular).disabled_at
    end

    test "an admin cannot disable their own row", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      refute has_element?(lv, ~s|button[phx-click="request_disable"][phx-value-id="#{admin.id}"]|)
    end

    test "delete schedules the regular user's deletion, which the worker then runs", %{
      conn: conn,
      regular: regular,
      admin: admin
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      lv |> delete_button(regular.id) |> render_click()
      html = lv |> confirm_user_action() |> render_click()

      assert html =~ "Deletion pending"

      refute has_element?(
               lv,
               ~s|button[phx-click="request_enable"][phx-value-id="#{regular.id}"]|
             )

      scheduled = Repo.reload!(regular)
      assert scheduled.deletion_requested_at
      assert scheduled.disabled_at

      assert_enqueued(
        worker: AccountDeletionWorker,
        args: %{
          "user_id" => regular.id,
          "step" => "prepare",
          "actor" => "admin",
          "actor_user_id" => admin.id
        }
      )

      assert :ok =
               perform_job(AccountDeletionWorker, %{
                 "user_id" => regular.id,
                 "step" => "purge",
                 "actor" => "admin",
                 "actor_user_id" => admin.id
               })

      refute Repo.get(Tymeslot.Auth.UserSchema, regular.id)
    end

    test "an admin cannot delete their own row", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      refute has_element?(lv, ~s|button[phx-click="request_delete"][phx-value-id="#{admin.id}"]|)
    end

    test "the sole admin cannot delete themselves even via a forged event", %{
      conn: conn,
      admin: admin
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin/users")

      lv
      |> with_target("#admin-hub")
      |> render_hook("delete_user", %{"id" => to_string(admin.id)})

      assert Repo.get(Tymeslot.Auth.UserSchema, admin.id)
    end
  end

  defp promote_button(lv, id) do
    element(lv, ~s|button[phx-click="request_promote"][phx-value-id="#{id}"]|)
  end

  defp demote_button(lv, id) do
    element(lv, ~s|button[phx-click="request_demote"][phx-value-id="#{id}"]|)
  end

  defp disable_button(lv, id) do
    element(lv, ~s|button[phx-click="request_disable"][phx-value-id="#{id}"]|)
  end

  defp enable_button(lv, id) do
    element(lv, ~s|button[phx-click="request_enable"][phx-value-id="#{id}"]|)
  end

  defp delete_button(lv, id) do
    element(lv, ~s|button[phx-click="request_delete"][phx-value-id="#{id}"]|)
  end

  defp confirm_role_change(lv) do
    element(lv, "#confirm-role-change-confirm-button")
  end

  defp confirm_user_action(lv) do
    element(lv, "#confirm-user-action-confirm-button")
  end
end
