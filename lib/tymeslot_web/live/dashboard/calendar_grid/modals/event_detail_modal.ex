defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.EventDetailModal do
  @moduledoc "Event detail/edit modal for viewing and editing calendar events."

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Integrations.Calendar.Attendee
  alias Tymeslot.Integrations.Calendar.Recurrence.RRule
  alias TymeslotWeb.Components.Dashboard.Meetings.AttendeeAttachments
  alias TymeslotWeb.Components.UI.StatusSwitch
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.AttendeeEditor
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.CalendarPicker
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.FormParts
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.RecurrenceEditor
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.RemindersEditor
  alias TymeslotWeb.Dashboard.CalendarGrid.VideoPicker
  alias TymeslotWeb.Helpers.LocaleFormat

  attr :selected_event, :map, required: true
  attr :integrations, :list, required: true
  attr :integration_colors, :map, required: true
  attr :calendar_colors, :map, required: true
  attr :user_timezone, :string, required: true
  attr :time_format, :string, default: "12h"
  attr :myself, :any, required: true
  attr :editable, :boolean, default: false
  attr :read_only, :boolean, default: false, doc: "the event's calendar takes no writes"
  attr :attendee_input, :string, default: ""
  attr :pending_attendees, :list, default: []
  attr :video_integrations, :list, default: []
  attr :pending_notification, :boolean, default: false

  attr :title_rev, :integer,
    default: 0,
    doc: "keys the title form, so a change re-renders the field with the saved title"

  @spec event_detail_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def event_detail_modal(assigns) do
    assigns =
      assigns
      |> assign(:attendees, attendees(assigns.selected_event))
      |> assign(:locale, Gettext.get_locale(TymeslotWeb.Gettext))

    ~H"""
    <.modal
      id="event-detail-modal"
      show={true}
      on_cancel={JS.push("close_event_detail", target: @myself)}
      size={:medium}
    >
      <:header>
        <form
          :if={@editable}
          id={"event-title-form-#{@title_rev}"}
          phx-change="update_event_title"
          phx-target={@myself}
          phx-submit="commit_event_title"
        >
          <FormParts.title_input
            id="event-title-input"
            value={@selected_event.summary || ""}
            placeholder={dgettext("dashboard_calendar_events", "(No title)")}
            required
            phx-blur="commit_event_title"
            phx-target={@myself}
            phx-debounce="500"
          />
        </form>
        <span :if={!@editable} class="block truncate">
          {@selected_event.summary || dgettext("dashboard_calendar_events", "(No title)")}
        </span>
      </:header>

      <div class="space-y-6 quiet-placeholders">
        <%!-- Pending-notification banner --%>
        <div
          :if={@pending_notification}
          class="rounded-lg bg-primary-50 dark:bg-primary-950/40 border border-primary-200 dark:border-primary-700 p-2 flex items-center justify-between"
        >
          <span class="text-token-sm text-primary-900 dark:text-primary-200">
            {dgettext("dashboard_calendar_events", "Attendees will be notified of pending changes.")}
          </span>
          <button
            type="button"
            phx-click="cancel_pending_notification"
            phx-target={@myself}
            class="text-token-sm text-primary-800 dark:text-primary-300 hover:text-primary-900 underline"
          >
            {dgettext("dashboard_calendar_events", "Cancel")}
          </button>
        </div>

        <%!-- Where the event comes from: its calendar's colour, and whether this
              app created it or its calendar takes no writes. --%>
        <div class="flex flex-wrap items-center gap-3">
          <div
            data-testid="event-colour-bar"
            class={"h-1 rounded-full w-10 #{Helpers.color_for_event(assigns, @selected_event)}"}
          >
          </div>
          <div
            :if={Map.get(@selected_event, :created_by_tymeslot)}
            class="flex items-center gap-1 text-token-xs text-neutral-500 dark:text-twilight-indigo-300"
          >
            <img src="/images/brand/logo.svg" alt="" class="w-3.5 h-3.5" />
            <span>{dgettext("dashboard_calendar_events", "Created by %{app_name}",
              app_name: Config.app_name()
            )}</span>
          </div>
          <span
            :if={@read_only}
            data-testid="read-only-calendar-notice"
            class="inline-flex items-center gap-1.5 rounded-token-full border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-950/40 px-3 py-1 text-token-xs font-bold text-amber-800 dark:text-amber-300"
          >
            <.icon name="hero-lock-closed-mini" class="w-3.5 h-3.5" />
            {dgettext("dashboard_calendar_events", "Calendar is read-only")}
          </span>
        </div>

        <%!-- Time --%>
        <div class="space-y-3">
          <% start_parts = Helpers.datetime_to_local_parts(@selected_event.start_at, @user_timezone) %>
          <% end_parts = Helpers.datetime_to_local_parts(@selected_event.end_at, @user_timezone) %>
          <%!-- end_date is stored exclusively; the field shows the inclusive last day. --%>
          <FormParts.date_time_range
            :if={@editable and @selected_event.all_day}
            id_prefix="event-all-day"
            event="update_event_all_day_range"
            target={@myself}
            start_date={@selected_event.start_date && Date.to_iso8601(@selected_event.start_date)}
            end_date={
              @selected_event.end_date && Date.to_iso8601(Date.add(@selected_event.end_date, -1))
            }
            all_day={true}
          />
          <FormParts.date_time_range
            :if={@editable and not @selected_event.all_day}
            id_prefix="event"
            form_id="event-time-form"
            event="update_event_time"
            target={@myself}
            start_date={start_parts.date}
            start_time={start_parts.time}
            end_date={end_parts.date}
            end_time={end_parts.time}
          />
          <div :if={@editable} class="flex items-center justify-between gap-4">
            <div class="flex items-center gap-3">
              <StatusSwitch.status_switch
                id="event-all-day"
                checked={@selected_event.all_day || false}
                on_change="toggle_event_all_day"
                target={@myself}
                size={:small}
                disabled={true}
                aria_label={dgettext("dashboard_calendar_events", "All day")}
              />
              <span class="text-token-sm font-medium text-neutral-700 dark:text-twilight-indigo-100">
                {dgettext("dashboard_calendar_events", "All day")}
              </span>
            </div>
            <FormParts.time_zone_note
              :if={not @selected_event.all_day}
              abbr={Helpers.tz_abbr(@user_timezone)}
            />
          </div>
          <div :if={!@editable}>
            <FormParts.section_label>
              {dgettext("dashboard_calendar_events", "Time")}
            </FormParts.section_label>
            <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
              <span :if={@selected_event.all_day}>{dgettext("dashboard_calendar_events", "All day")}</span>
              <span :if={!@selected_event.all_day}>
                {Helpers.format_time_range_in_tz(@selected_event, @user_timezone, @time_format)}
                <span class="text-token-xs font-normal text-neutral-400 ml-1">{Helpers.tz_abbr(
                  @user_timezone
                )}</span>
              </span>
            </p>
            <p class="text-token-xs text-neutral-400 mt-0.5">
              {LocaleFormat.format_weekday_day_month(
                Helpers.event_display_date(@selected_event, @user_timezone),
                @locale
              )}
            </p>
          </div>
        </div>

        <FormParts.divider />

        <%!-- Calendar and video. The picker only offers the calendar the event
              is already in: moving an event is a drag on the grid. --%>
        <div
          :if={@editable}
          class="grid gap-4 sm:grid-cols-2"
        >
          <div>
            <% owning_integration =
              Enum.find(@integrations, &(&1.id == @selected_event.calendar_integration_id)) %>
            <% owning_calendar_id =
              CalendarPicker.derive_event_calendar_id(@selected_event, owning_integration) %>
            <FormParts.section_label for="event-calendar">
              {dgettext("dashboard_calendar_events", "Calendar")}
            </FormParts.section_label>
            <CalendarPicker.calendar_picker
              id="event-calendar"
              integrations={
                owning_integration
                |> List.wrap()
                |> Enum.map(&narrow_to_calendar(&1, owning_calendar_id))
              }
              integration_colors={@integration_colors}
              selected_integration_id={@selected_event.calendar_integration_id}
              selected_calendar_id={owning_calendar_id}
              myself={@myself}
              event_name="update_event_calendar"
            />
          </div>
          <div :if={@video_integrations != []}>
            <FormParts.section_label for="event-video">
              {dgettext("dashboard_calendar_events", "Video")}
            </FormParts.section_label>
            <VideoPicker.video_picker
              id="event-video"
              video_integrations={@video_integrations}
              selected_id={Map.get(@selected_event, :video_integration_id)}
              target={@myself}
              phx_event="update_edit_video"
            />
          </div>
        </div>

        <%!-- Repeat and reminders: shown, not changed here. --%>
        <div :if={@editable} class="grid gap-4 sm:grid-cols-2">
          <RecurrenceEditor.recurrence_editor
            recurrence_rule={Map.get(@selected_event, :recurrence_rule)}
            timezone={Shared.recurrence_timezone(@selected_event, @user_timezone)}
            myself={@myself}
            change_event="update_event_recurrence"
            read_only={true}
          />
          <RemindersEditor.reminders_editor
            reminders={Map.get(@selected_event, :reminders) || []}
            myself={@myself}
            add_event="add_event_reminder"
            remove_event="remove_event_reminder"
            read_only={true}
          />
        </div>
        <div
          :if={
            !@editable and
              (recurrence_summary(@selected_event, @user_timezone) != nil or
                 (Map.get(@selected_event, :reminders) || []) != [])
          }
          class="grid gap-4 sm:grid-cols-2"
        >
          <div :if={recurrence_summary(@selected_event, @user_timezone) != nil}>
            <FormParts.section_label>
              {dgettext("dashboard_calendar_events", "Repeat")}
            </FormParts.section_label>
            <p class="text-token-sm text-neutral-600 dark:text-neutral-300 leading-snug">
              {recurrence_summary(@selected_event, @user_timezone)}
            </p>
          </div>
          <div :if={(Map.get(@selected_event, :reminders) || []) != []}>
            <FormParts.section_label>
              {dgettext("dashboard_calendar_events", "Reminder")}
            </FormParts.section_label>
            <p
              :for={reminder <- Map.get(@selected_event, :reminders) || []}
              class="text-token-sm text-neutral-600 dark:text-neutral-300 leading-snug"
            >
              {RemindersEditor.reminder_label(reminder)}
            </p>
          </div>
        </div>

        <%!-- Location --%>
        <div :if={@editable}>
          <FormParts.section_label for="event-location-input">
            {dgettext("dashboard_calendar_events", "Location")}
          </FormParts.section_label>
          <.input
            type="text"
            id="event-location-input"
            name="value"
            value={@selected_event.location || ""}
            placeholder={dgettext("dashboard_calendar_events", "Add location")}
            phx-blur="update_event_location"
            phx-target={@myself}
            phx-debounce="500"
          />
        </div>
        <div :if={!@editable and @selected_event.location}>
          <FormParts.section_label>
            {dgettext("dashboard_calendar_events", "Location")}
          </FormParts.section_label>
          <a
            :if={Helpers.url?(@selected_event.location)}
            href={@selected_event.location}
            target="_blank"
            rel="noopener noreferrer"
            class="text-token-sm text-primary-600 hover:text-primary-800 underline break-all"
          >
            {@selected_event.location}
          </a>
          <p
            :if={!Helpers.url?(@selected_event.location)}
            class="text-token-sm text-neutral-600 dark:text-neutral-300"
          >
            {@selected_event.location}
          </p>
        </div>

        <%!-- Description --%>
        <div :if={@editable}>
          <FormParts.section_label for="event-description-input">
            {dgettext("dashboard_calendar_events", "Description")}
          </FormParts.section_label>
          <.input
            type="textarea"
            id="event-description-input"
            name="value"
            value={@selected_event.description || ""}
            placeholder={dgettext("dashboard_calendar_events", "Add description")}
            rows={4}
            phx-blur="update_event_description"
            phx-target={@myself}
            phx-debounce="500"
          />
        </div>
        <div :if={!@editable and @selected_event.description}>
          <FormParts.section_label>
            {dgettext("dashboard_calendar_events", "Description")}
          </FormParts.section_label>
          <div class="text-token-sm text-neutral-600 dark:text-neutral-300 max-h-52 overflow-y-auto whitespace-pre-line break-words leading-relaxed">
            {Helpers.linkify_text(@selected_event.description)}
          </div>
        </div>

        <%!-- The booker's files, on the synced copy of a booking (annotated by
             `Tymeslot.CalendarGrid.BookingEvents`); served to the organiser only. --%>
        <div
          :if={Map.get(@selected_event, :booking_meeting_id)}
          data-testid="event-attendee-attachments"
        >
          <FormParts.section_label>
            {dgettext("dashboard_calendar_events", "Attachments")}
          </FormParts.section_label>
          <AttendeeAttachments.links
            meeting_id={@selected_event.booking_meeting_id}
            attachments={Map.get(@selected_event, :attendee_attachments, [])}
          />
        </div>

        <%!-- Attendees --%>
        <AttendeeEditor.attendee_editor
          editable={@editable}
          attendees={@attendees}
          pending_attendees={@pending_attendees}
          attendee_input={@attendee_input}
          myself={@myself}
          read_only={true}
        />
      </div>

      <:footer>
        <div class="flex gap-2">
          <.action_button
            variant={:secondary}
            phx-click={JS.push("close_event_detail", target: @myself)}
          >
            {dgettext("dashboard_calendar_events", "Cancel")}
          </.action_button>
          <.action_button
            :if={@editable}
            variant={:danger}
            phx-click="request_delete_event"
            phx-target={@myself}
          >
            {dgettext("dashboard_calendar_events", "Delete event")}
          </.action_button>
        </div>
      </:footer>
    </.modal>
    """
  end

  # Narrows an integration's calendar_list down to the single calendar an
  # event belongs to, so the calendar picker only ever displays the one
  # calendar the event is already stored in.
  defp narrow_to_calendar(integration, nil), do: integration

  defp narrow_to_calendar(%{calendar_list: calendar_list} = integration, calendar_id)
       when is_list(calendar_list) do
    %{integration | calendar_list: Enum.filter(calendar_list, &(&1.id == calendar_id))}
  end

  defp narrow_to_calendar(integration, _calendar_id), do: integration

  # Read-only human-readable summary of an event's recurrence rule, or nil when
  # the event does not repeat. The rule's UNTIL is an instant written in UTC, so
  # it is read back in the zone it was written against, the event's own.
  defp recurrence_summary(event, user_timezone) do
    case Map.get(event, :recurrence_rule) do
      rule when is_binary(rule) and rule != "" ->
        rule
        |> RRule.parse(timezone: Shared.recurrence_timezone(event, user_timezone))
        |> RecurrenceEditor.summary()

      _none ->
        nil
    end
  end

  # Cached attendees come back from JSONB string-keyed, while one the organiser
  # has just added is still atom-keyed in memory, so the editor reads them all
  # in the one canonical shape.
  defp attendees(event) do
    event
    |> Map.get(:attendees)
    |> List.wrap()
    |> Enum.map(&Attendee.normalise/1)
  end
end
