defmodule TymeslotWeb.Components.Dashboard.Meetings.MeetingCardComponents do
  @moduledoc """
  The meeting card shown in the dashboard bookings list: attendee/schedule
  details, guest RSVP list, calendar-sync-drift banner, and per-status action
  buttons.

  Split out of `MeetingListComponents` (which renders the list/filter shell
  around this card) purely to keep each module under the dashboard page-size
  guideline — `meeting_card/1` and its exclusively-supporting helpers below
  are not reused anywhere else.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.CustomFields.AnswerRenderer
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.MeetingState
  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers
  alias TymeslotWeb.Components.Dashboard.Meetings.MeetingStatusBadge

  # Meeting Card
  attr :meeting, :map, required: true
  attr :profile, :any, required: false
  attr :time_format, :string, required: true
  attr :cancelling_meeting, :any, required: false
  attr :sending_reschedule, :any, required: false
  attr :answering_request, :any, default: nil
  attr :deleting_meeting, :any, required: false
  attr :target, :any, required: true

  @spec meeting_card(map()) :: Phoenix.LiveView.Rendered.t()
  def meeting_card(assigns) do
    ~H"""
    <div class="card-glass hover:bg-white dark:hover:bg-twilight-indigo-900 hover:border-primary-100 dark:hover:border-primary-800 hover:shadow-2xl hover:shadow-primary-500/5 group/card">
      <.calendar_sync_banner
        :if={
          @meeting.calendar_sync_status in [
            "externally_deleted",
            "externally_modified",
            "creation_failed"
          ] and
            is_nil(@meeting.calendar_sync_status_dismissed_at)
        }
        meeting={@meeting}
        target={@target}
      />
      <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-8">
        <div class="flex-1">
          <div class="flex items-center gap-3 flex-wrap mb-6">
            <h4 class="text-token-2xl font-black text-neutral-900 dark:text-neutral-100 tracking-tight group-hover/card:text-primary-700 transition-colors">
              {@meeting.attendee_name}
            </h4>
            <span
              :if={@meeting.attendee_company}
              class="text-token-sm font-black text-neutral-700 dark:text-neutral-300 bg-neutral-100 dark:bg-twilight-indigo-900 px-3 py-1 rounded-token-lg"
            >
              {@meeting.attendee_company}
            </span>
            <MeetingStatusBadge.status_badges meeting={@meeting} />
            <span
              :if={@meeting.meeting_url}
              class="inline-flex items-center gap-1.5 px-3 py-1 bg-secondary-50 dark:bg-secondary-950/40 text-secondary-700 dark:text-secondary-300 text-token-xs font-black uppercase tracking-wider rounded-full border border-secondary-100 dark:border-secondary-800 shadow-sm"
            >
              <CoreComponents.icon name="hero-video-camera" class="w-3.5 h-3.5" />
              {dgettext("dashboard_bookings", "Video Call")}
            </span>
          </div>

          <div class="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-token-2xl bg-primary-50 dark:bg-primary-950/30 flex items-center justify-center shadow-sm border border-primary-100 dark:border-primary-800 transition-transform group-hover/card:scale-110">
                <CoreComponents.icon
                  name="hero-calendar-days"
                  class="w-6 h-6 text-primary-600 dark:text-primary-400"
                />
              </div>
              <div>
                <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mb-0.5">
                  {dgettext("dashboard_bookings", "Date & Time")}
                </p>
                <p class="text-neutral-700 dark:text-neutral-300 font-bold">
                  {Helpers.format_meeting_date(
                    @meeting,
                    Helpers.get_meeting_timezone(@meeting, @profile)
                  )}
                  <span class="text-primary-600 ml-1">
                    {Helpers.format_meeting_time(
                      @meeting,
                      Helpers.get_meeting_timezone(@meeting, @profile),
                      @time_format
                    )}
                  </span>
                </p>
              </div>
            </div>

            <div
              :if={
                @meeting.status == "cancelled" &&
                  Helpers.format_cancelled_at_date(
                    @meeting,
                    Helpers.get_meeting_timezone(@meeting, @profile)
                  )
              }
              class="flex items-center gap-4"
            >
              <div class="w-12 h-12 rounded-token-2xl bg-red-50 dark:bg-red-950/30 flex items-center justify-center shadow-sm border border-red-100 dark:border-red-800 transition-transform group-hover/card:scale-110">
                <CoreComponents.icon
                  name="hero-x-circle"
                  class="w-6 h-6 text-red-600 dark:text-red-400"
                />
              </div>
              <div>
                <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mb-0.5">
                  {dgettext("dashboard_bookings", "Cancelled On")}
                </p>
                <p class="text-neutral-700 dark:text-neutral-300 font-bold">
                  {Helpers.format_cancelled_at_date(
                    @meeting,
                    Helpers.get_meeting_timezone(@meeting, @profile)
                  )}
                </p>
              </div>
            </div>

            <div class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-token-2xl bg-blue-50 dark:bg-blue-950/30 flex items-center justify-center shadow-sm border border-blue-100 dark:border-blue-800 transition-transform group-hover/card:scale-110">
                <CoreComponents.icon
                  name="hero-envelope"
                  class="w-6 h-6 text-blue-600 dark:text-blue-400"
                />
              </div>
              <div>
                <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mb-0.5">
                  {dgettext("dashboard_bookings", "Attendee Email")}
                </p>
                <a
                  href={"mailto:#{@meeting.attendee_email}"}
                  class="text-neutral-700 dark:text-neutral-300 hover:text-primary-600 transition-colors font-bold"
                >
                  {@meeting.attendee_email}
                </a>
              </div>
            </div>

            <div :if={@meeting.attendee_phone} class="flex items-center gap-4">
              <div class="w-12 h-12 rounded-token-2xl bg-green-50 dark:bg-green-950/30 flex items-center justify-center shadow-sm border border-green-100 dark:border-green-800 transition-transform group-hover/card:scale-110">
                <CoreComponents.icon
                  name="hero-phone"
                  class="w-6 h-6 text-green-600 dark:text-green-400"
                />
              </div>
              <div>
                <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mb-0.5">
                  Attendee Phone
                </p>
                <a
                  href={"tel:#{@meeting.attendee_phone}"}
                  class="text-neutral-700 dark:text-neutral-300 hover:text-primary-600 transition-colors font-bold"
                >
                  {@meeting.attendee_phone}
                </a>
              </div>
            </div>
          </div>

          <div
            :if={guest_list(@meeting) != []}
            class="mt-8 p-5 bg-neutral-50/50 dark:bg-twilight-indigo-900/40 rounded-token-2xl border-2 border-neutral-300 dark:border-twilight-indigo-800"
          >
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-4">
                <div class="w-8 h-8 rounded-token-lg bg-white dark:bg-twilight-indigo-950 shadow-sm flex items-center justify-center shrink-0 border border-neutral-300 dark:border-twilight-indigo-700">
                  <CoreComponents.icon name="hero-user-group" class="w-4 h-4 text-neutral-400" />
                </div>
                <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest">
                  {dgettext("dashboard_bookings", "Guests")}
                </p>
              </div>
              <span class="text-token-sm font-bold text-neutral-500 dark:text-neutral-400">
                {guest_summary_label(@meeting)}
              </span>
            </div>
            <ul class="space-y-2.5">
              <li
                :for={guest <- guest_list(@meeting)}
                class="flex items-center justify-between gap-3"
              >
                <span class="flex items-center gap-2.5 min-w-0">
                  <span class="flex h-7 w-7 flex-none items-center justify-center rounded-token-full bg-primary-100 dark:bg-primary-900 text-token-xs font-bold uppercase text-primary-700 dark:text-primary-300">
                    {guest_initial(guest)}
                  </span>
                  <span class="truncate text-token-sm font-medium text-neutral-700 dark:text-neutral-300">
                    {guest.name || guest.email}
                  </span>
                </span>
                <.guest_status_badge status={guest.status} />
              </li>
            </ul>
          </div>

          <div
            :if={@meeting.attendee_message && @meeting.attendee_message != ""}
            class="mt-8 p-5 bg-neutral-50/50 dark:bg-twilight-indigo-900/40 rounded-token-2xl border-2 border-neutral-300 dark:border-twilight-indigo-800"
          >
            <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mb-1">
              {dgettext("dashboard_bookings", "Meeting Notes")}
            </p>
            <p class="text-neutral-600 dark:text-neutral-300 font-medium leading-relaxed">
              {@meeting.attendee_message}
            </p>
          </div>

          <% displayable_fields =
            Enum.filter(@meeting.custom_fields_snapshot, fn field ->
              @meeting.custom_field_answers[field["id"]]
              |> then(&AnswerRenderer.render(field, &1))
              |> Kernel.!=("")
            end) %>
          <div
            :if={displayable_fields != []}
            class="mt-8 p-5 bg-neutral-50/50 dark:bg-twilight-indigo-900/40 rounded-token-2xl border-2 border-neutral-300 dark:border-twilight-indigo-800"
          >
            <div class="flex gap-4 items-start mb-4">
              <div class="w-8 h-8 rounded-token-lg bg-white dark:bg-twilight-indigo-950 shadow-sm flex items-center justify-center shrink-0 border border-neutral-300 dark:border-twilight-indigo-700">
                <CoreComponents.icon name="hero-list-bullet" class="w-4 h-4 text-neutral-400" />
              </div>
              <p class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mt-2">
                {dgettext("dashboard_bookings", "Custom answers")}
              </p>
            </div>
            <dl class="space-y-3">
              <div
                :for={field <- displayable_fields}
                class="grid grid-cols-1 md:grid-cols-[1fr_2fr] gap-x-6 gap-y-1"
              >
                <dt class="text-token-sm font-semibold text-neutral-500 dark:text-neutral-400">
                  {field["label"]}
                </dt>
                <dd class="text-token-sm text-neutral-700 dark:text-neutral-300 font-medium">
                  {AnswerRenderer.render(field, @meeting.custom_field_answers[field["id"]])}
                </dd>
              </div>
            </dl>
          </div>
        </div>

        <div class="flex lg:flex-col gap-3 shrink-0 lg:w-[160px]">
          <%!-- A held request offers exactly two actions. Join, Reschedule and
                Cancel all presuppose a meeting that is happening, and offering
                them here is what let a host "reschedule" a booking they had
                never agreed to. --%>
          <div :if={MeetingState.awaiting_approval?(@meeting)} class="contents">
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
            <a
              :if={@meeting.meeting_url}
              href={@meeting.meeting_url}
              target="_blank"
              rel="noopener noreferrer"
              class="btn btn-primary py-3 px-4 text-token-sm w-full flex items-center justify-center whitespace-nowrap"
            >
              <CoreComponents.icon name="hero-video-camera" class="w-4 h-4 mr-2 shrink-0" />
              {dgettext("dashboard_bookings", "Join Meeting")}
            </a>

            <button
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
          <div :if={@meeting.status == "cancelled"} class="contents">
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
      </div>
    </div>
    """
  end

  attr :meeting, :map, required: true
  attr :target, :any, required: true

  defp calendar_sync_banner(assigns) do
    ~H"""
    <div class={[
      "flex items-start justify-between gap-4 rounded-2xl px-5 py-4 mb-6 border-2",
      if(@meeting.calendar_sync_status == "externally_deleted",
        do:
          "bg-red-50 dark:bg-red-950/40 border-red-200 dark:border-red-800 text-red-800 dark:text-red-200",
        else:
          "bg-amber-50 dark:bg-amber-950/40 border-amber-200 dark:border-amber-800 text-amber-800 dark:text-amber-200"
      )
    ]}>
      <p class="font-medium text-token-sm">
        <span :if={@meeting.calendar_sync_status == "externally_deleted"}>
          {dgettext(
            "dashboard_bookings",
            "This meeting's event was deleted from your external calendar."
          )}
        </span>
        <span :if={@meeting.calendar_sync_status == "externally_modified"}>
          {dgettext(
            "dashboard_bookings",
            "This meeting's event was rescheduled in your external calendar."
          )}
        </span>
        <span :if={@meeting.calendar_sync_status == "creation_failed"}>
          {dgettext(
            "dashboard_bookings",
            "This meeting's event could not be added to your external calendar."
          )}
        </span>
      </p>
      <button
        phx-click="dismiss_calendar_sync_banner"
        phx-value-id={@meeting.id}
        phx-target={@target}
        class="modal-icon-button modal-icon-button--sm shrink-0"
        aria-label={dgettext("dashboard_bookings", "Dismiss")}
      >
        <CoreComponents.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </div>
    """
  end

  # Small coloured pill reflecting a guest's RSVP status.
  attr :status, :string, required: true

  defp guest_status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex flex-none items-center gap-1 rounded-full px-2.5 py-0.5 text-token-xs font-bold",
      guest_badge_classes(@status)
    ]}>
      <CoreComponents.icon name={guest_badge_icon(@status)} class="w-3.5 h-3.5" />
      {guest_status_label(@status)}
    </span>
    """
  end

  defp guest_badge_classes("accepted"),
    do:
      "bg-green-50 dark:bg-green-950/40 text-green-700 dark:text-green-300 border border-green-100 dark:border-green-800"

  defp guest_badge_classes("declined"),
    do:
      "bg-red-50 dark:bg-red-950/40 text-red-600 dark:text-red-300 border border-red-100 dark:border-red-800"

  defp guest_badge_classes(_pending),
    do:
      "bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300 border border-amber-100 dark:border-amber-800"

  defp guest_badge_icon("accepted"), do: "hero-check-circle-mini"
  defp guest_badge_icon("declined"), do: "hero-x-circle-mini"
  defp guest_badge_icon(_pending), do: "hero-clock-mini"

  defp guest_status_label("accepted"), do: dgettext("dashboard_bookings", "Going")
  defp guest_status_label("declined"), do: dgettext("dashboard_bookings", "Declined")
  defp guest_status_label(_pending), do: dgettext("dashboard_bookings", "Pending")

  defp guest_list(%{guests: guests}) when is_list(guests), do: guests
  defp guest_list(_meeting), do: []

  defp guest_initial(%{name: name}) when is_binary(name) and name != "",
    do: name |> String.first() |> String.upcase()

  defp guest_initial(%{email: email}) when is_binary(email) and email != "",
    do: email |> String.first() |> String.upcase()

  defp guest_initial(_guest), do: "?"

  defp guest_summary_label(meeting) do
    summary = Meetings.guest_rsvp_summary(guest_list(meeting))

    dgettext("dashboard_bookings", "%{going} of %{total} going",
      going: summary.accepted,
      total: summary.total
    )
  end
end
