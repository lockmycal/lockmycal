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
  alias TymeslotWeb.Components.CoreComponents
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
    <div class="flex lg:flex-col gap-3 shrink-0 lg:w-[160px]">
      <%!-- A held request offers exactly two actions. Join, Reschedule and
              Cancel all presuppose a meeting that is happening, and offering
              them here is what let a host "reschedule" a booking they had
              never agreed to. --%>
      <%!-- Only the organiser answers a request: the attendee who sent it
              sees it waiting, with the status badge saying on whom. --%>
      <div
        :if={
          MeetingState.awaiting_approval?(@meeting) and
            Meetings.organized_by?(@meeting, @current_user_email)
        }
        class="contents"
      >
        <button
          id={"approve-request-#{@meeting.id}"}
          phx-click="approve_request"
          phx-value-id={@meeting.id}
          phx-target={@target}
          disabled={@answering_request == @meeting.id}
          data-testid="approve-request"
          class="btn btn-success py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap disabled:opacity-50"
        >
          <CoreComponents.spinner :if={@answering_request == @meeting.id} class="h-4 w-4 mr-2" />
          <CoreComponents.icon
            :if={@answering_request != @meeting.id}
            name="hero-check"
            class="w-4 h-4 mr-2 shrink-0"
          />
          {dgettext("dashboard_bookings", "Approve")}
        </button>

        <button
          phx-click="show_decline_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          disabled={@answering_request == @meeting.id}
          data-testid="decline-request"
          class="btn btn-danger py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap disabled:opacity-50"
        >
          <CoreComponents.icon name="hero-x-mark" class="w-4 h-4 mr-2 shrink-0" />
          {dgettext("dashboard_bookings", "Decline")}
        </button>
      </div>

      <div
        :if={
          @meeting.status != "cancelled" && !MeetingState.awaiting_approval?(@meeting) &&
            !Helpers.past_meeting?(@meeting)
        }
        class="contents"
      >
        <%!-- The attendee joins by their own link, the host keeps the
              meeting's (which a host room may moderate). --%>
        <a
          :if={join_url(@meeting, @attending?)}
          href={join_url(@meeting, @attending?)}
          target="_blank"
          rel="noopener noreferrer"
          class="btn btn-primary py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap"
        >
          <CoreComponents.icon name="hero-video-camera" class="w-4 h-4 mr-2 shrink-0" />
          {dgettext("dashboard_bookings", "Join Meeting")}
        </a>

        <%!-- Inviting guests and asking the attendee to pick another time
              are the host's: the user who booked elsewhere may only cancel,
              which notifies the host. --%>
        <button
          :if={!@attending? && Helpers.can_add_guests?(@meeting)}
          id={"add-guests-#{@meeting.id}"}
          phx-click="show_add_guests_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          data-testid="add-guests"
          class="btn btn-success py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap"
        >
          <CoreComponents.icon name="hero-user-plus" class="w-4 h-4 mr-2 shrink-0" />
          {dgettext("dashboard_bookings", "Add guest")}
        </button>

        <button
          :if={!@attending?}
          phx-click="show_reschedule_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          disabled={!Helpers.can_reschedule?(@meeting)}
          class={[
            "btn btn-secondary py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap",
            if(!Helpers.can_reschedule?(@meeting), do: "opacity-50 cursor-not-allowed", else: "")
          ]}
        >
          <CoreComponents.icon name="hero-arrows-right-left" class="w-4 h-4 mr-2 shrink-0" />
          {dgettext("dashboard_bookings", "Reschedule")}
        </button>

        <button
          id={"cancel-meeting-#{@meeting.id}"}
          phx-click="show_cancel_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          disabled={@cancelling_meeting == @meeting.id || !Helpers.can_cancel?(@meeting)}
          class={[
            "btn btn-danger py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap",
            if(!Helpers.can_cancel?(@meeting), do: "opacity-50 cursor-not-allowed", else: "")
          ]}
        >
          <span :if={@cancelling_meeting == @meeting.id} class="flex items-center">
            <CoreComponents.spinner class="h-4 w-4 mr-2" /> {dgettext(
              "dashboard_bookings",
              "Processing..."
            )}
          </span>
          <span :if={@cancelling_meeting != @meeting.id} class="flex items-center">
            <CoreComponents.icon name="hero-x-mark" class="w-4 h-4 mr-2 shrink-0" /> {dgettext(
              "dashboard_bookings",
              "Cancel"
            )}
          </span>
        </button>
      </div>
      <div
        :if={
          @meeting.status == "cancelled" and
            Meetings.organized_by?(@meeting, @current_user_email)
        }
        class="contents"
      >
        <button
          id={"delete-meeting-#{@meeting.id}"}
          phx-click="show_delete_modal"
          phx-value-id={@meeting.id}
          phx-target={@target}
          disabled={@deleting_meeting == @meeting.id}
          class="btn btn-danger py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap"
        >
          <span :if={@deleting_meeting == @meeting.id} class="flex items-center">
            <CoreComponents.spinner class="h-4 w-4 mr-2" /> {dgettext(
              "dashboard_bookings",
              "Deleting..."
            )}
          </span>
          <span :if={@deleting_meeting != @meeting.id} class="flex items-center">
            <CoreComponents.icon name="hero-trash" class="w-4 h-4 mr-2 shrink-0" /> {dgettext(
              "dashboard_bookings",
              "Delete"
            )}
          </span>
        </button>
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

  defp join_url(meeting, false = _attending?), do: meeting.meeting_url
end
