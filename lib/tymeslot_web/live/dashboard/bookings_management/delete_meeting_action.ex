defmodule TymeslotWeb.Dashboard.BookingsManagement.DeleteMeetingAction do
  @moduledoc """
  The manual-delete flow for an already-cancelled meeting: show/hide the
  confirmation modal and perform the hard delete
  (`Tymeslot.Meetings.delete_meeting_for_user/2` — there is no undo).

  Split out of `BookingsManagementComponent` purely to keep that module
  under the dashboard page-size guideline, mirroring how `ComponentView` was
  split out for markup — this only handles the `delete_meeting` modal's
  three events, nothing reused elsewhere.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.Bookings.Policy
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Meetings
  alias TymeslotWeb.Dashboard.BookingsManagementComponent
  alias TymeslotWeb.Hooks.ModalHook
  alias TymeslotWeb.Live.Shared.Flash

  require Logger

  @spec show_modal(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def show_modal(socket, params) do
    case BookingsManagementComponent.fetch_meeting_for_modal(socket, params,
           policy_fun: &Policy.can_delete_meeting?/1
         ) do
      {:ok, meeting} ->
        {:noreply, ModalHook.show_modal(socket, :delete_meeting, meeting)}

      {:error, :policy_blocked, reason} ->
        Flash.error(reason)
        {:noreply, socket}

      {:error, _tag, _reason} ->
        {:noreply, socket}
    end
  end

  @spec hide_modal(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def hide_modal(socket), do: {:noreply, ModalHook.hide_modal(socket, :delete_meeting)}

  @spec confirm(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def confirm(socket) do
    ModalHook.with_modal_data(socket, :delete_meeting, fn meeting -> run(socket, meeting) end)
  end

  defp run(socket, meeting) do
    socket = assign(socket, :deleting_meeting, meeting.id)
    user_email = socket.assigns.current_user.email

    case Meetings.delete_meeting_for_user(meeting, user_email) do
      {:ok, _deleted} ->
        Flash.info(dgettext("dashboard_bookings", "Meeting deleted"))

        {:noreply,
         socket
         |> assign(:deleting_meeting, nil)
         |> BookingsManagementComponent.load_meetings()
         |> ModalHook.hide_modal(:delete_meeting)}

      {:error, error_reason} ->
        Logger.error("delete_meeting_failed",
          reason: LogFormat.reason(error_reason),
          meeting_id: meeting.id
        )

        Flash.error(dgettext("dashboard_bookings", "Failed to delete meeting. Please try again."))
        {:noreply, assign(socket, :deleting_meeting, nil)}
    end
  end
end
