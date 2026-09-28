defmodule TymeslotWeb.Dashboard.ProfileSettingsPasswordTest do
  @moduledoc """
  Password settings, moved from the old standalone `/dashboard/account` page
  into `PasswordSettingsFormComponent` on the Profile page. See
  `ProfileSettingsEmailTest` for why this is a separate file.
  """

  use TymeslotWeb.LiveCase, async: false
  @moduletag :profiles
  @moduletag :live

  import Tymeslot.AuthTestHelpers
  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Onboarding
  alias Tymeslot.Security.RateLimiter

  setup :setup_dashboard_user

  setup do
    RateLimiter.clear_all()
    :ok
  end

  describe "rendering" do
    test "shows the always-visible form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Password"
      assert html =~ "Current Password"
      assert html =~ "Update Password"
    end
  end

  describe "changing the password" do
    test "redirects to login with explanatory flash on success", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> form("form[phx-submit='update_password']", %{
        "password_form" => %{
          "current_password" => "Password123!",
          "new_password" => "NewPassword123!",
          "new_password_confirmation" => "NewPassword123!"
        }
      })
      |> render_submit()

      flash = assert_redirect(view, ~p"/auth/login")

      assert flash["info"] =~
               "Your password has been changed. Please sign in again with your new password."
    end

    test "shows error for password mismatch", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      html =
        view
        |> form("form[phx-submit='update_password']", %{
          "password_form" => %{
            "current_password" => "Password123!",
            "new_password" => "NewPassword123!",
            "new_password_confirmation" => "Mismatch123!"
          }
        })
        |> render_submit()

      assert html =~ "does not match"
    end

    test "shows error for short password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      html =
        view
        |> form("form[phx-submit='update_password']", %{
          "password_form" => %{
            "current_password" => "Password123!",
            "new_password" => "short",
            "new_password_confirmation" => "short"
          }
        })
        |> render_submit()

      assert html =~ "at least 8 characters"
    end

    test "shows error when new password matches the current one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      html =
        view
        |> form("form[phx-submit='update_password']", %{
          "password_form" => %{
            "current_password" => "Password123!",
            "new_password" => "Password123!",
            "new_password_confirmation" => "Password123!"
          }
        })
        |> render_submit()

      assert html =~ "different from current"
    end
  end

  describe "rate limiting" do
    setup %{user: user} do
      # Exhaust the account-wide auth ceiling (50 per 30 minutes); it applies
      # whatever address the request comes from.
      Enum.each(1..50, fn _i ->
        RateLimiter.check_rate("login:#{user.email}", 1_800_000, 50)
      end)

      :ok
    end

    test "shows rate limit error when password change limit is exceeded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> form("form[phx-submit='update_password']", %{
        "password_form" => %{
          "current_password" => "Password123!",
          "new_password" => "NewPassword123!",
          "new_password_confirmation" => "NewPassword123!"
        }
      })
      |> render_submit()

      # The rate-limit error is forwarded via a `send/2` + `handle_info/2`
      # cycle that runs after render_submit already returned.
      :sys.get_state(view.pid)
      assert render(view) =~ "reached the limit"
    end
  end

  describe "social login users" do
    setup %{conn: conn} do
      user = insert(:user, provider: "google")
      {:ok, user} = Onboarding.mark_onboarding_complete(user)
      profile = insert(:profile, user: user)
      %{conn: log_in_user(conn, user), user: user, profile: profile}
    end

    test "shows a managed-by message instead of the form", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Authentication is managed through Google"
      refute html =~ "Current Password"
    end

    test "update is a no-op for social users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      target = with_target(view, "#password-settings-form-container")
      render_submit(target, "update_password", %{"password_form" => %{"current_password" => ""}})

      # The error is forwarded to the parent LiveView via a `send/2` +
      # `handle_info/2` cycle that runs after render_submit already
      # returned — drain the mailbox before re-reading the flash.
      :sys.get_state(view.pid)
      assert render(view) =~ "Google"
    end
  end
end
