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
  import Tymeslot.Factory

  alias Tymeslot.MeetingTypes

  setup :setup_dashboard_user

  test "switching it on saves it", %{conn: conn, user: user} do
    meeting_type = insert(:meeting_type, user: user, name: "Free time")

    {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

    view
    |> element("button[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
    |> render_click()

    view
    |> element("button[phx-click='toggle_show_as_free'][phx-value-state='true']")
    |> render_click()

    assert %{show_as_free: true} = MeetingTypes.get_meeting_type(meeting_type.id, user.id)
  end
end
