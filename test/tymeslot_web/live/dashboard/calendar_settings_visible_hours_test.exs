defmodule TymeslotWeb.Dashboard.CalendarSettingsVisibleHoursTest do
  @moduledoc """
  Coverage for the "Public calendar" block of
  `TymeslotWeb.Dashboard.CalendarSettingsComponent`: its layout, the
  on/off switch, and the "Visible hours" row — the daily time-of-day window
  that clips which busy blocks the public calendar page and the free/busy ICS
  feed expose (`Tymeslot.FreeBusy.clip_to_visible_window/4`).

  Split out of `CalendarSettingsCompositionTest` to keep both files under
  the project's line-count budget, not because this scenario differs from
  the rest of that suite's style.
  """
  use TymeslotWeb.LiveCase, async: false

  @moduletag :integration
  @moduletag :integrations
  @moduletag :calendar
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Profiles.ProfileQueries

  setup :setup_dashboard_user

  describe "weekends row" do
    test "is off by default and the toggle persists both ways", %{conn: conn, user: user} do
      {:ok, before} = ProfileQueries.get_by_user_id(user.id)
      refute before.public_calendar_show_weekends

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")

      view
      |> element("button[phx-click='toggle_public_calendar_show_weekends']", "Enabled")
      |> render_click()

      {:ok, after_enable} = ProfileQueries.get_by_user_id(user.id)
      assert after_enable.public_calendar_show_weekends

      view
      |> element("button[phx-click='toggle_public_calendar_show_weekends']", "Disabled")
      |> render_click()

      {:ok, after_disable} = ProfileQueries.get_by_user_id(user.id)
      refute after_disable.public_calendar_show_weekends
    end
  end

  describe "public calendar block" do
    test "groups every public calendar setting into one block, visibility first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")

      block = view |> element("#public-calendar-settings") |> render()

      positions =
        Enum.map(
          ["Visibility", "Colour settings", "Visible hours", "Weekends", "Historical events"],
          &elem(:binary.match(block, &1), 0)
        )

      assert positions == Enum.sort(positions)
    end

    test "switching the public calendar off persists and on again restores it", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")

      view
      |> element("button[phx-click='toggle_public_calendar_enabled'][phx-value-state='false']")
      |> render_click()

      {:ok, after_disable} = ProfileQueries.get_by_user_id(user.id)
      refute after_disable.public_calendar_enabled

      view
      |> element("button[phx-click='toggle_public_calendar_enabled'][phx-value-state='true']")
      |> render_click()

      {:ok, after_enable} = ProfileQueries.get_by_user_id(user.id)
      assert after_enable.public_calendar_enabled
    end
  end

  describe "public calendar visible hours" do
    test "enabling seeds a default 9-5 window, editing it persists, disabling clears it", %{
      conn: conn,
      user: user
    } do
      {:ok, view, html} = live(conn, ~p"/dashboard/calendar-integration")
      refute html =~ "public-calendar-visible-hours-form"

      view
      |> element(
        "button[phx-click='toggle_public_calendar_visible_hours'][phx-value-state='true']"
      )
      |> render_click()

      {:ok, after_enable} = ProfileQueries.get_by_user_id(user.id)
      assert after_enable.public_calendar_visible_from == ~T[09:00:00]
      assert after_enable.public_calendar_visible_to == ~T[17:00:00]
      assert has_element?(view, "#public-calendar-visible-hours-form")

      view
      |> form("form[phx-change='update_public_calendar_visible_hours']", %{
        "from" => "07:00",
        "to" => "18:00"
      })
      |> render_change()

      {:ok, after_update} = ProfileQueries.get_by_user_id(user.id)
      assert after_update.public_calendar_visible_from == ~T[07:00:00]
      assert after_update.public_calendar_visible_to == ~T[18:00:00]

      view
      |> element(
        "button[phx-click='toggle_public_calendar_visible_hours'][phx-value-state='false']"
      )
      |> render_click()

      {:ok, after_disable} = ProfileQueries.get_by_user_id(user.id)
      assert is_nil(after_disable.public_calendar_visible_from)
      assert is_nil(after_disable.public_calendar_visible_to)
      refute has_element?(view, "#public-calendar-visible-hours-form")
    end

    test "an end time before the start time is rejected with a flash, DB unchanged", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")

      view
      |> element(
        "button[phx-click='toggle_public_calendar_visible_hours'][phx-value-state='true']"
      )
      |> render_click()

      view
      |> form("form[phx-change='update_public_calendar_visible_hours']", %{
        "from" => "18:00",
        "to" => "07:00"
      })
      |> render_change()

      assert render(view) =~ "End time must be after the start time"

      {:ok, profile} = ProfileQueries.get_by_user_id(user.id)
      assert profile.public_calendar_visible_from == ~T[09:00:00]
      assert profile.public_calendar_visible_to == ~T[17:00:00]
    end
  end
end
