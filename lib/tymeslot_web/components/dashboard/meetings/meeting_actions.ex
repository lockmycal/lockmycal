defmodule TymeslotWeb.Components.Dashboard.Meetings.MeetingActions do
  @moduledoc """
  The column of actions on a booking card.

  Split out of `MeetingListComponents` so each module stays within the
  project's size limit, and because what a host may do with a booking is a
  subject of its own: a held request offers only approve and decline, a live
  booking offers join, guests, reschedule and cancel, a cancelled one offers
  its organiser a permanent delete, and a past one offers nothing at all.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.MeetingState
  alias TymeslotWeb.Components.Dashboard.Appointments.JoinLink
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers

  attr :meeting, :map, required: true
  attr :target, :any, required: true
  attr :answering_request, :any, required: true
  attr :cancelling_meeting, :any, required: true
  attr :deleting_meeting, :any, default: nil
  attr :current_user_email, :string, default: nil

  attr :attending?, :boolean,
    default: false,
    doc: "a booking the user made on someone else's page (`Meetings.attended_by?/2`)"

  @doc "The action column for one booking card."
  @spec action_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def action_bar(assigns) do
    ~H"""
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:flex lg:flex-col gap-3 shrink-0 lg:w-[160px]">
      <%!-- A held request offers exactly two actions. Join, Reschedule and
              Cancel all presuppose a meeting that is happening, and offering
              them here is what let a host "reschedule" a booking they had
              never agreed to. --%>
      <%!-- Decline and Cancel use the soft destructive style: they sit beside
              the action the card is for and must not outweigh it. The solid red
              button is the confirm inside the modal each one opens. --%>
      <%!-- Only the organiser answers a request: the attendee who sent it
              sees it waiting, with the status badge saying on whom. --%>
      <div
        :if={
          MeetingState.awaiting_approval?(@meeting) and
            Meetings.organized_by?(@meeting, @current_user_email)
        }
        class="contents"
      >
        <.loading_button
          id={"approve-request-#{@meeting.id}"}
          phx-click="approve_request"
          phx-value-id={@meeting.id}
          phx-target={@target}
          loading={@answering_request == @meeting.id}
          loading_text={dgettext("dashboard_bookings", "Approve")}
          data-testid="approve-request"
          size={:sm}
          icon="hero-check"
          class="w-full"
        >
          {dgettext("dashboard_bookings", "Approve")}
        </.loading_button>

        <.action_button
          phx-click="show_decline_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          disabled={@answering_request == @meeting.id}
          data-testid="decline-request"
          variant={:danger_soft}
          size={:sm}
          icon="hero-x-mark"
          class="w-full"
        >
          {dgettext("dashboard_bookings", "Decline")}
        </.action_button>
      </div>

      <div
        :if={
          @meeting.status != "cancelled" && !MeetingState.awaiting_approval?(@meeting) &&
            !Helpers.past_meeting?(@meeting)
        }
        class="contents"
      >
        <%!-- The attendee joins by their own link, the host keeps the
              meeting's (which a host room may moderate). Wraps rather than
              overflowing the 160px desktop column: most translations of
              "Join meeting" are wider than it. --%>
        <JoinLink.join_link
          :if={join_url(@meeting, @attending?)}
          url={join_url(@meeting, @attending?)}
          size={:sm}
          class="w-full whitespace-normal text-center"
        />

        <%!-- Inviting guests and asking the attendee to pick another time
              are the host's: the user who booked elsewhere may only cancel,
              which notifies the host. --%>
        <.action_button
          :if={!@attending? && Helpers.can_add_guests?(@meeting)}
          id={"add-guests-#{@meeting.id}"}
          phx-click="show_add_guests_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          data-testid="add-guests"
          variant={:success}
          size={:sm}
          icon="hero-user-plus"
          class="w-full"
        >
          {dgettext("dashboard_bookings", "Add guest")}
        </.action_button>

        <.action_button
          :if={!@attending?}
          phx-click="show_reschedule_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          disabled={!Helpers.can_reschedule?(@meeting)}
          variant={:secondary}
          size={:sm}
          icon="hero-arrows-right-left"
          class="w-full"
        >
          {dgettext("dashboard_bookings", "Reschedule")}
        </.action_button>

        <.loading_button
          id={"cancel-meeting-#{@meeting.id}"}
          phx-click="show_cancel_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          loading={@cancelling_meeting == @meeting.id}
          loading_text={dgettext("dashboard_bookings", "Processing...")}
          disabled={!Helpers.can_cancel?(@meeting)}
          variant={:danger_soft}
          size={:sm}
          icon="hero-x-mark"
          class="w-full"
        >
          {dgettext("dashboard_bookings", "Cancel")}
        </.loading_button>
      </div>
      <div
        :if={
          @meeting.status == "cancelled" and
            Meetings.organized_by?(@meeting, @current_user_email)
        }
        class="contents"
      >
        <.loading_button
          id={"delete-meeting-#{@meeting.id}"}
          phx-click="show_delete_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          loading={@deleting_meeting == @meeting.id}
          loading_text={dgettext("dashboard_bookings", "Deleting...")}
          variant={:danger_soft}
          size={:sm}
          icon="hero-trash"
          class="w-full"
        >
          {dgettext("dashboard_bookings", "Delete")}
        </.loading_button>
      </div>
      <div
        :if={
          @meeting.status != "cancelled" and Helpers.past_meeting?(@meeting) and
            not MeetingState.awaiting_approval?(@meeting)
        }
        class="hidden lg:block"
      >
        &nbsp;
      </div>
    </div>
    """
  end

  defp join_url(meeting, true = _attending?),
    do: meeting.attendee_video_url || meeting.meeting_url

  defp join_url(meeting, false = _attending?), do: Meetings.organizer_join_url(meeting)
end
