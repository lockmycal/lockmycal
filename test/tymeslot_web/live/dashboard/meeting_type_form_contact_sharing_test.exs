defmodule TymeslotWeb.Dashboard.MeetingTypeFormContactSharingTest do
  @moduledoc """
  Whether a signed-in booker sees the host's email and phone: two toggles per
  meeting type, off until the host turns them on.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :meeting_types
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.MeetingTypes

  setup :setup_dashboard_user

  # A new meeting type is created from the Details tab alone, so it starts
  # with the defaults of every other tab.
  defp create(conn, name) do
    {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")
    view |> element("button", "Add Meeting Type") |> render_click()

    view
    |> form("form[phx-submit='create_meeting_type']", %{
      "meeting_type" => %{"name" => name, "duration" => "30"}
    })
    |> render_submit()

    view
  end

  defp saved(user, name),
    do: Enum.find(MeetingTypes.get_all_meeting_types(user.id), &(&1.name == name))

  test "shares nothing unless the host switches it on", %{conn: conn, user: user} do
    create(conn, "Private")

    assert %{show_email_to_bookers: false, show_phone_to_bookers: false} =
             saved(user, "Private")
  end

  test "saves the email and phone the host chose to share", %{conn: conn, user: user} do
    # Creating switches the same form to editing the new type, where the
    # Booking Rules tab and its auto-save are available.
    view = create(conn, "Shared")

    for event <- ~w(toggle_show_email_to_bookers toggle_show_phone_to_bookers) do
      view
      |> element("button[phx-click='#{event}'][phx-value-state='true']")
      |> render_click()
    end

    assert %{show_email_to_bookers: true, show_phone_to_bookers: true} = saved(user, "Shared")
  end
end
