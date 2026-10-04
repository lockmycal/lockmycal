defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.BookingDetailModal do
  @moduledoc """
  Read-only detail modal for a Tymeslot booking shown on the calendar grid.

  Bookings are managed through the booking flows (cancel with refund handling,
  reschedule requests) rather than edited like provider events, so this modal
  presents the booking and links to the Meetings page for those actions.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Tymeslot.Infrastructure.Config
  alias TymeslotWeb.Components.Dashboard.Meetings.AttendeeAttachments
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.FormParts
  alias TymeslotWeb.Helpers.LocaleFormat

  attr :booking, :map, required: true
  attr :user_timezone, :string, required: true
  attr :time_format, :any, default: nil
  attr :myself, :any, required: true

  @spec booking_detail_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def booking_detail_modal(assigns) do
    ~H"""
    <.modal
      id="booking-detail-modal"
      show={true}
      on_cancel={JS.push("close_booking_detail", target: @myself)}
      size={:medium}
    >
      <:header>
        <div class="flex items-center gap-2 min-w-0">
          <img src="/images/brand/logo.svg" alt="" class="w-5 h-5 shrink-0" />
          <span class="truncate">{@booking.summary}</span>
        </div>
      </:header>

      <div class="space-y-6" data-testid="booking-detail">
        <div>
          <FormParts.section_label>
            {dgettext("dashboard_calendar_events", "Time")}
          </FormParts.section_label>
          <div class="text-token-sm font-medium text-neutral-800 dark:text-neutral-100">
            {booking_date_label(@booking, @user_timezone)}
          </div>
          <div class="text-token-sm text-neutral-500 dark:text-twilight-indigo-300">
            {Helpers.format_display_time_range(@booking, @time_format, @user_timezone)}
          </div>
        </div>

        <div :if={@booking.attendee_name || @booking.attendee_email} class="min-w-0">
          <FormParts.section_label>
            {dgettext("dashboard_calendar_events", "Guest")}
          </FormParts.section_label>
          <div
            :if={@booking.attendee_name}
            class="text-token-sm font-medium text-neutral-800 dark:text-neutral-100"
          >
            {@booking.attendee_name}
          </div>
          <div
            :if={@booking.attendee_email}
            class="text-token-sm text-neutral-500 dark:text-twilight-indigo-300 truncate"
          >
            {@booking.attendee_email}
          </div>
        </div>

        <div :if={@booking.location} class="min-w-0">
          <FormParts.section_label>
            {dgettext("dashboard_calendar_events", "Location")}
          </FormParts.section_label>
          <div class="text-token-sm text-neutral-700 dark:text-neutral-200 break-words">
            {@booking.location}
          </div>
        </div>

        <div :if={@booking.description} class="min-w-0">
          <FormParts.section_label>
            {dgettext("dashboard_bookings", "Meeting Type")}
          </FormParts.section_label>
          <%!-- phx-no-format: under whitespace-pre-line the formatter's line
               break before the value would render as a blank first line. --%>
          <div
            phx-no-format
            class="text-token-sm text-neutral-700 dark:text-neutral-200 max-h-52 overflow-y-auto whitespace-pre-line break-words leading-relaxed"
          >{Helpers.linkify_text(@booking.description)}</div>
        </div>

        <div :if={@booking.attendee_message} class="min-w-0">
          <FormParts.section_label>
            {dgettext("dashboard_bookings", "Meeting Notes")}
          </FormParts.section_label>
          <div
            phx-no-format
            class="text-token-sm text-neutral-700 dark:text-neutral-200 max-h-52 overflow-y-auto whitespace-pre-line break-words leading-relaxed"
          >{@booking.attendee_message}</div>
        </div>

        <div :if={@booking.attendee_attachments != []} class="min-w-0">
          <FormParts.section_label>
            {dgettext("dashboard_bookings", "Attachments")}
          </FormParts.section_label>
          <AttendeeAttachments.links
            meeting_id={@booking.meeting_id}
            attachments={@booking.attendee_attachments}
          />
        </div>

        <FormParts.divider />

        <div class="flex items-center gap-2 text-token-xs text-neutral-500 dark:text-twilight-indigo-300">
          <.icon name="hero-check-badge" class="w-4 h-4 text-primary-500" />
          {dgettext("dashboard_calendar", "Booked through your %{app_name} booking page",
            app_name: Config.app_name()
          )}
        </div>
      </div>

      <:footer>
        <div class="flex flex-wrap gap-2">
          <.action_button
            variant={:secondary}
            phx-click={JS.push("close_booking_detail", target: @myself)}
          >
            {dgettext("dashboard_calendar_events", "Cancel")}
          </.action_button>
          <a
            :if={@booking.join_url}
            href={@booking.join_url}
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white text-token-sm font-semibold rounded-token-lg transition-colors"
          >
            <.icon name="hero-video-camera" class="w-4 h-4" />
            {dgettext("dashboard_calendar", "Join meeting")}
          </a>
          <.link
            patch={~p"/dashboard/meetings"}
            class="btn btn-primary gap-2 text-token-sm"
          >
            <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
            {dgettext("dashboard_calendar", "Manage in Meetings")}
          </.link>
        </div>
      </:footer>
    </.modal>
    """
  end

  defp booking_date_label(booking, timezone) do
    booking
    |> Helpers.event_display_date(timezone)
    |> LocaleFormat.format_weekday_date(Gettext.get_locale(TymeslotWeb.Gettext))
  end
end
