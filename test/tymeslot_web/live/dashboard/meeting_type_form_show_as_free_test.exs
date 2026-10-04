defmodule TymeslotWeb.Dashboard.MeetingTypeFormShowAsFreeTest do
  @moduledoc """
  The "show these bookings as free on my calendar" switch is saved with the
  meeting type, so bookings of it are written to the host's calendar as free.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :meeting_types
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.MeetingTypes

  setup :setup_dashboard_user

  test "switching it on saves it", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")
    view |> element("button", "Add Meeting Type") |> render_click()
    view |> element("button[aria-label='Remove reminder']") |> render_click()

    view
    |> element("button[phx-click='toggle_show_as_free'][phx-value-state='true']")
    |> render_click()

    view
    |> form("form[phx-submit='save_meeting_type']", %{
      "meeting_type" => %{"name" => "Free time", "duration" => "30"}
    })
    |> render_submit()

    assert %{show_as_free: true} =
             Enum.find(MeetingTypes.get_all_meeting_types(user.id), &(&1.name == "Free time"))
  end
end
