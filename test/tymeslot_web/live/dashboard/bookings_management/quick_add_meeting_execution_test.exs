defmodule TymeslotWeb.Dashboard.BookingsManagement.QuickAddMeetingExecutionTest do
  @moduledoc """
  Covers `save_event/2`'s meeting-mode authorization guard: a `creating_event`
  whose `integration_id` doesn't belong to the current user (e.g. a tampered
  client param — the picker only ever offers the user's own integrations)
  must be rejected before `CreateAdHoc.execute/1` runs, same as the
  calendar's own `CreateExecution.handle_save_event_with/2` (meeting mode).
  """

  use Tymeslot.DataCase, async: true

  @moduletag :meetings
  @moduletag :live

  import Tymeslot.Factory

  alias TymeslotWeb.Dashboard.BookingsManagement.QuickAddMeetingExecution

  defp build_socket(creating_overrides) do
    user = insert(:user)

    creating =
      Map.merge(
        %{
          mode: :meeting,
          guest_name: "Ada Lovelace",
          guest_email: "ada@example.com",
          title: nil,
          integration_id: nil,
          calendar_id: nil,
          video_integration_id: nil,
          reminders: [],
          date: "2026-04-10",
          end_date: "2026-04-10",
          start_hour: 10,
          start_minute: 0,
          end_hour: 11,
          end_minute: 0
        },
        creating_overrides
      )

    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flash: %{},
        current_user: user,
        profile: nil,
        creating_event: creating,
        owned_integration_ids: MapSet.new(),
        filter: "upcoming"
      }
    }
  end

  describe "save_event/2 — meeting mode, unowned integration" do
    test "flashes 'Invalid calendar selected' and does not book the meeting" do
      other_integration = insert(:calendar_integration, is_active: true)

      socket = build_socket(%{integration_id: other_integration.id})

      {:noreply, updated_socket} = QuickAddMeetingExecution.save_event(%{}, socket)

      assert_received {:flash, {:error, "Invalid calendar selected"}}
      # Rejected before booking: the dialog stays open on the still-set creating_event.
      assert updated_socket.assigns.creating_event == socket.assigns.creating_event
    end
  end

  # The no-integration / happy-path case is already covered end to end by
  # "a valid submission books the meeting and closes the modal" in
  # BookingsManagementQuickAddTest.
end
