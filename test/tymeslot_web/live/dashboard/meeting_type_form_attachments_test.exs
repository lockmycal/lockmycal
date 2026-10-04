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

  defp open_new_form(conn) do
    {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")
    view |> element("button", "Add Meeting Type") |> render_click()
    view |> element("button[aria-label='Remove reminder']") |> render_click()
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

    view = open_new_form(conn)
    refute has_element?(view, "#meeting-type-attachment-limits")

    html = switch(view, "true")
    assert html =~ "PDF, DOCX"
    assert html =~ "7 MB"

    view
    |> form("form[phx-submit='save_meeting_type']", %{
      "meeting_type" => %{"name" => "With files", "duration" => "30"}
    })
    |> render_submit()

    assert %{allow_attachments: true} =
             Enum.find(MeetingTypes.get_all_meeting_types(user.id), &(&1.name == "With files"))
  end

  test "is disabled when the admin allows no file type", %{conn: conn} do
    {:ok, _settings} = AppSettings.update(%{booking_attachment_types: []})

    html = render(open_new_form(conn))
    assert html =~ "switched file attachments off"
  end
end
