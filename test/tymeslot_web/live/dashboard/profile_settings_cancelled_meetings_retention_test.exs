defmodule TymeslotWeb.Dashboard.ProfileSettingsCancelledMeetingsRetentionTest do
  @moduledoc """
  Covers the Cancelled Meetings section of Profile Settings: the toggle that
  opts a user into auto-deleting their own cancelled meetings, and the days
  field controlling how long they're kept after cancellation.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :profiles
  @moduletag :live

  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Profiles

  setup :setup_dashboard_user

  describe "the Cancelled Meetings section" do
    test "is offered on the settings page, enabled by default", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Cancelled Meetings"
      assert html =~ "Automatically delete cancelled meetings?"
      assert html =~ "Delete after (days since cancellation)"
      assert Profiles.get_profile(user.id).auto_delete_cancelled_meetings_enabled
    end

    test "enabling it stores the setting", %{conn: conn, user: user} do
      turn_off(user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element(
        "button[phx-click='toggle_auto_delete_cancelled_meetings'][phx-value-state='true']"
      )
      |> render_click()

      assert Profiles.get_profile(user.id).auto_delete_cancelled_meetings_enabled
    end

    test "confirms the change to the organiser", %{conn: conn, user: user} do
      turn_off(user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element(
        "button[phx-click='toggle_auto_delete_cancelled_meetings'][phx-value-state='true']"
      )
      |> render_click()

      # The flash is raised by the component but rendered by the parent
      # LiveView, so it only appears once the parent has re-rendered.
      assert render(view) =~ "Cancelled meetings will now be deleted automatically"
    end

    test "reveals the days field once enabled", %{conn: conn, user: user} do
      turn_off(user)
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      refute render(view) =~ "Delete after (days since cancellation)"

      view
      |> element(
        "button[phx-click='toggle_auto_delete_cancelled_meetings'][phx-value-state='true']"
      )
      |> render_click()

      assert render(view) =~ "Delete after (days since cancellation)"
    end

    test "changing the days field persists immediately", %{conn: conn, user: user} do
      Profiles.update_profile_field(
        Profiles.get_profile(user.id),
        :auto_delete_cancelled_meetings_enabled,
        true
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("input[name='after_days']")
      |> render_change(%{"after_days" => "45"})

      assert Profiles.get_profile(user.id).auto_delete_cancelled_meetings_after_days ==
               45
    end

    test "rejects an out-of-range days value and keeps the old one", %{conn: conn, user: user} do
      Profiles.update_profile_field(
        Profiles.get_profile(user.id),
        :auto_delete_cancelled_meetings_enabled,
        true
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("input[name='after_days']")
      |> render_change(%{"after_days" => "0"})

      assert render(view) =~ "Cleanup delay must be between"

      assert Profiles.get_profile(user.id).auto_delete_cancelled_meetings_after_days ==
               30
    end

    test "disabling it turns the setting back off", %{conn: conn, user: user} do
      Profiles.update_profile_field(
        Profiles.get_profile(user.id),
        :auto_delete_cancelled_meetings_enabled,
        true
      )

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element(
        "button[phx-click='toggle_auto_delete_cancelled_meetings'][phx-value-state='false']"
      )
      |> render_click()

      refute Profiles.get_profile(user.id).auto_delete_cancelled_meetings_enabled
    end
  end

  defp turn_off(user) do
    Profiles.update_profile_field(
      Profiles.get_profile(user.id),
      :auto_delete_cancelled_meetings_enabled,
      false
    )
  end
end
