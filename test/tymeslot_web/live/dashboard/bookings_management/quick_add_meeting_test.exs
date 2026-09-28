defmodule TymeslotWeb.Dashboard.BookingsManagement.QuickAddMeetingTest do
  @moduledoc """
  Covers `QuickAddMeeting` handlers that must no-op instead of crashing when
  `creating_event` is `nil` — e.g. a stray/late `phx-change` event delivered
  after the dialog has already been closed (a race between an in-flight
  debounce and `close_create_form`/`discard_pending_attendees`).
  """

  use Tymeslot.DataCase, async: true

  @moduletag :meetings
  @moduletag :live

  alias TymeslotWeb.Dashboard.BookingsManagement.QuickAddMeeting

  defp socket_with_no_creating_event do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, creating_event: nil}}
  end

  describe "update_create_time/2 — no in-progress event" do
    test "is a no-op instead of raising" do
      socket = socket_with_no_creating_event()

      assert {:noreply, ^socket} =
               QuickAddMeeting.update_create_time(
                 %{"start-date" => "2026-04-10", "start-time" => "10:00"},
                 socket
               )
    end
  end

  describe "put_field/3-backed handlers — no in-progress event" do
    test "update_create_title/2 is a no-op instead of raising" do
      socket = socket_with_no_creating_event()

      assert {:noreply, ^socket} =
               QuickAddMeeting.update_create_title(%{"value" => "Standup"}, socket)
    end

    test "update_create_guest_name/2 is a no-op instead of raising" do
      socket = socket_with_no_creating_event()

      assert {:noreply, ^socket} =
               QuickAddMeeting.update_create_guest_name(%{"value" => "Ada Lovelace"}, socket)
    end

    test "update_create_guest_email/2 is a no-op instead of raising" do
      socket = socket_with_no_creating_event()

      assert {:noreply, ^socket} =
               QuickAddMeeting.update_create_guest_email(%{"value" => "ada@example.com"}, socket)
    end
  end
end
