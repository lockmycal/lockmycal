defmodule Tymeslot.DashboardTestHelpers do
  @moduledoc """
  Helper functions for dashboard tests.
  """
  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers
  import Phoenix.ConnTest
  import Plug.Conn

  @doc """
  Sets up a user with a profile and logs them in.
  """
  @spec setup_dashboard_user(map()) :: {:ok, keyword()}
  def setup_dashboard_user(%{conn: conn}) do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    profile = insert(:profile, user: user)
    conn = conn |> init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user, profile: profile}
  end

  @doc """
  Sets up a user with a profile (including theme) and logs them in.
  """
  @spec setup_dashboard_user_with_theme(map(), String.t()) :: {:ok, keyword()}
  def setup_dashboard_user_with_theme(%{conn: conn}, theme_id \\ "1") do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    profile = insert(:profile, user: user, booking_theme: theme_id)
    conn = conn |> init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user, profile: profile}
  end
end
