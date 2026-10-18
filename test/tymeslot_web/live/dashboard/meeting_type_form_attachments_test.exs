defmodule TymeslotWeb.Dashboard.MeetingTypeFormAttachmentsTest do
  @moduledoc """
  The host's only attachment control: switching the booking-page field on or
  off per meeting type. The limits it shows are the admin's.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :meeting_types
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.AppSettings
  alias Tymeslot.MeetingTypes

  setup :setup_dashboard_user

  setup do
    original = Application.get_env(:tymeslot, :uploads)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:tymeslot, :uploads)
        value -> Application.put_env(:tymeslot, :uploads, value)
      end
    end)

    :ok
  end

  # The switch sits on the Booking Rules tab, which only exists once the
  # meeting type does, and every change there auto-saves.
  defp open_form(conn, meeting_type) do
    {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

    view
    |> element("button[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
    |> render_click()

    view
  end

  defp switch(view, state) do
    view
    |> element("button[phx-click='toggle_allow_attachments'][phx-value-state='#{state}']")
    |> render_click()
  end

  test "switching it on shows the admin's limits and saves", %{conn: conn, user: user} do
    {:ok, _settings} =
      AppSettings.update(%{
        booking_attachment_types: ["pdf", "docx"],
        max_booking_attachment_size_mb: 7,
        max_booking_attachments: 2
      })

    meeting_type = insert(:meeting_type, user: user, name: "With files")
    view = open_form(conn, meeting_type)
    refute has_element?(view, "#meeting-type-attachment-limits")

    html = switch(view, "true")
    assert html =~ "PDF, DOCX"
    assert html =~ "7 MB"

    assert %{allow_attachments: true} = MeetingTypes.get_meeting_type(meeting_type.id, user.id)
  end

  test "is disabled when the admin allows no file type", %{conn: conn, user: user} do
    {:ok, _settings} = AppSettings.update(%{booking_attachment_types: []})

    html = render(open_form(conn, insert(:meeting_type, user: user)))
    assert html =~ "switched file attachments off"
  end
end
