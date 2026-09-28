defmodule TymeslotWeb.Dashboard.ProfileSettingsEmailTest do
  @moduledoc """
  Email settings, moved from the old standalone `/dashboard/account` page
  into `EmailSettingsFormComponent` on the Profile page. Split out of
  `ProfileSettingsRateLimitingTest`/friends purely to stay under the credo
  module line-count limit — see `ProfileSettingsPasswordTest` for the
  Password form's coverage.
  """

  use TymeslotWeb.LiveCase, async: false
  @moduletag :profiles
  @moduletag :live

  import Tymeslot.AuthTestHelpers
  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Auth
  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Onboarding
  alias Tymeslot.Repo
  alias Tymeslot.Security.RateLimiter
  alias TymeslotWeb.Helpers.ClientIP

  setup :setup_dashboard_user

  setup do
    RateLimiter.clear_all()
    :ok
  end

  describe "rendering" do
    test "shows the current email and the always-visible form", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Email Address"
      assert html =~ user.email
      assert html =~ "New Email Address"
    end
  end

  describe "requesting an email change" do
    test "updates email with valid data", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      new_email = "new-email@example.com"

      view
      |> form("form[phx-submit='update_email']", %{
        "email_form" => %{
          "new_email" => new_email,
          "current_password" => "Password123!"
        }
      })
      |> render_submit()

      assert render(view) =~ "Email Change Pending"
      assert render(view) =~ new_email

      updated_user = Repo.get(UserSchema, user.id)
      assert updated_user.pending_email == new_email
    end

    test "shows error for incorrect password", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      html =
        view
        |> form("form[phx-submit='update_email']", %{
          "email_form" => %{
            "new_email" => "valid@example.com",
            "current_password" => "WrongPassword123!"
          }
        })
        |> render_submit()

      assert html =~ "Current password is incorrect"
    end

    test "can cancel a pending email change", %{conn: conn, user: user} do
      {:ok, user, _email_change_token} =
        Auth.request_email_change(
          user,
          "pending@example.com",
          "Password123!",
          ClientIP.request_opts(%Plug.Conn{})
        )

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert render(view) =~ "Email Change Pending"

      view |> element("button", "Cancel email change") |> render_click()

      refute render(view) =~ "Email Change Pending"

      updated_user = Repo.get(UserSchema, user.id)
      assert is_nil(updated_user.pending_email)
    end
  end

  describe "rate limiting" do
    setup %{user: user} do
      # Exhaust the account-wide auth ceiling (50 per 30 minutes) before each
      # test; it applies whatever address the request comes from.
      Enum.each(1..50, fn _i ->
        RateLimiter.check_rate("login:#{user.email}", 1_800_000, 50)
      end)

      :ok
    end

    test "shows rate limit error when email change limit is exceeded", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> form("form[phx-submit='update_email']", %{
        "email_form" => %{
          "new_email" => "new@example.com",
          "current_password" => "Password123!"
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

      assert html =~ "Managed through your Google account"
      refute html =~ "New Email Address"
    end

    test "update is a no-op for social users", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      target = with_target(view, "#email-settings-form-container")
      render_submit(target, "update_email", %{"email_form" => %{"new_email" => ""}})

      # The error is forwarded to the parent LiveView via a `send/2` +
      # `handle_info/2` cycle that runs after render_submit already
      # returned — drain the mailbox before re-reading the flash.
      :sys.get_state(view.pid)
      assert render(view) =~ "Google"
    end
  end
end
