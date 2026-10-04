defmodule TymeslotWeb.Dashboard.ProfileSettingsBookingTitleTest do
  @moduledoc """
  Covers the Meeting Titles section of Profile Settings: the control an
  organiser uses to choose whether bookings on their dashboard are named by the
  guest's meeting information or by the meeting type.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :profiles
  @moduletag :live

  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.CalendarGrid

  setup :setup_dashboard_user

  test "is offered on the settings page with both sources", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

    assert html =~ "Meeting Titles"
    assert html =~ "Meeting Information"
    assert html =~ "Meeting type"
  end

  test "defaults to the meeting information", %{user: user} do
    assert CalendarGrid.get_or_create_preferences(user.id).booking_title_source == "meeting_info"
  end

  test "stores the organiser's choice and confirms it", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

    view
    |> element("button[phx-click='change_booking_title_source'][phx-value-option='meeting_type']")
    |> render_click()

    assert CalendarGrid.get_or_create_preferences(user.id).booking_title_source == "meeting_type"
    assert render(view) =~ "Meeting titles updated"
  end

  test "ignores an unknown source", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

    view
    |> element("#booking-title-form-container button[phx-value-option='meeting_type']")
    |> render_click(%{"option" => "bogus"})

    assert CalendarGrid.get_or_create_preferences(user.id).booking_title_source == "meeting_info"
  end
end
