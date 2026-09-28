defmodule TymeslotWeb.Dashboard.ProfileSettingsDeleteAccountTest do
  @moduledoc """
  Covers the Danger zone on Profile Settings: deleting your own account,
  confirmed with your password (or, without one, your email).
  """

  use TymeslotWeb.LiveCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :profiles
  @moduletag :live
  @moduletag :auth

  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory, only: [insert: 2]
  import Tymeslot.MeetingTestHelpers, only: [insert_meeting_for_user: 2]

  alias Ecto.Changeset
  alias Phoenix.Flash
  alias Tymeslot.Repo
  alias Tymeslot.Workers.AccountDeletionWorker

  setup :setup_dashboard_user

  defp open_dialog(view) do
    view |> element("#delete-account-button") |> render_click()
  end

  defp submit(view, params) do
    view |> form("#delete-account-form", delete_account: params) |> render_submit()
  end

  test "the dialog asks for the password and says how many meetings will be cancelled", %{
    conn: conn,
    user: user
  } do
    insert_meeting_for_user(user, %{start_offset: 2 * 86_400})
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

    html = open_dialog(view)

    assert html =~ "Current Password"
    assert has_element?(view, "[data-testid='delete-account-upcoming']")
  end

  test "the dialog mentions Microsoft consent only for a user with an Outlook or Teams integration",
       %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
    open_dialog(view)
    refute has_element?(view, "[data-testid='delete-account-microsoft']")

    insert(:calendar_integration, user: user, provider: "outlook")
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

    html = open_dialog(view)

    assert has_element?(view, "[data-testid='delete-account-microsoft']")
    assert html =~ "myapps.microsoft.com"
  end

  test "a wrong password is refused inline and nothing is scheduled", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
    open_dialog(view)

    html = submit(view, %{current_password: "not-my-password"})

    assert html =~ "Current password is incorrect"
    refute Repo.reload!(user).deletion_requested_at
    refute_enqueued(worker: AccountDeletionWorker)
  end

  test "the right password hands over to the controller, which schedules the deletion", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
    open_dialog(view)

    form = form(view, "#delete-account-form", delete_account: %{current_password: "Password123!"})
    render_submit(form)

    # Nothing is scheduled from the LiveView itself.
    refute Repo.reload!(user).deletion_requested_at

    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == "/auth/login"
    assert Flash.get(conn.assigns.flash, :info) =~ "scheduled for deletion"
    assert Repo.reload!(user).deletion_requested_at

    assert_enqueued(
      worker: AccountDeletionWorker,
      args: %{"user_id" => user.id, "step" => "prepare", "actor" => "self"}
    )
  end

  test "an account without a password confirms with its email", %{conn: conn, user: user} do
    user |> Changeset.change(password_hash: nil, provider: "google") |> Repo.update!()
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

    html = open_dialog(view)
    assert html =~ "to confirm"
    refute html =~ "Current Password"

    assert submit(view, %{email_confirmation: "wrong@example.com"}) =~
             "This does not match your account email address"

    form = form(view, "#delete-account-form", delete_account: %{email_confirmation: user.email})
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert redirected_to(conn) == "/auth/login"
    assert Repo.reload!(user).deletion_requested_at
  end

  test "the controller re-checks the confirmation on its own", %{conn: conn, user: user} do
    conn =
      post(conn, ~p"/dashboard/settings/delete-account", %{
        "delete_account" => %{"current_password" => "not-my-password"}
      })

    assert redirected_to(conn) == "/dashboard/settings"
    refute Repo.reload!(user).deletion_requested_at
    refute_enqueued(worker: AccountDeletionWorker)
  end

  test "the last admin cannot delete their account", %{conn: conn, user: user} do
    user |> Changeset.change(is_admin: true) |> Repo.update!()
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

    assert has_element?(view, "[data-testid='delete-account-last-admin']")
    assert has_element?(view, "#delete-account-button[disabled]")
  end
end
