defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.CreateEventModal do
  @moduledoc "Create event modal for the calendar grid."

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  import TymeslotWeb.Components.UI.LocaleButton

  alias Phoenix.LiveView.JS
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Locales
  alias Tymeslot.Meetings.Guests
  alias Tymeslot.Meetings.MeetingSchema
  alias TymeslotWeb.Components.Dashboard.ContactPicker
  alias TymeslotWeb.Components.UI.StatusSwitch
  alias TymeslotWeb.Dashboard.CalendarGrid.EditWorkflow
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.CalendarPicker
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.FormParts
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.RecurrenceEditor
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.RemindersEditor
  alias TymeslotWeb.Dashboard.CalendarGrid.VideoPicker

  attr :creating_event, :map, required: true
  attr :integrations, :list, required: true
  attr :integration_colors, :map, required: true
  attr :saving, :boolean, default: false
  attr :user_timezone, :string, required: true
  attr :myself, :any, required: true
  attr :video_integrations, :list, default: []
  attr :contacts_allowed, :boolean, default: true
  attr :contact_picker_query, :string, default: ""
  attr :contact_picker_open, :boolean, default: false
  attr :contact_picker_results, :list, default: []

  attr :show_mode_toggle, :boolean,
    default: true,
    doc: """
    When `false`, hides the Event/Meeting tabs even with a calendar
    connected, locking the dialog into whatever `creating_event.mode`
    already is. Currently unused: both callers (the calendar grid and the
    Meetings page's own quick-add dialog) rely on the `true` default — the
    Meetings page's dialog supports both modes too, same as the calendar's.
    """

  @spec create_event_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def create_event_modal(assigns) do
    assigns =
      assigns
      |> assign(:meeting_mode, assigns.creating_event[:mode] == :meeting)
      # A subscribed calendar is no more a target than no calendar at all, so
      # the mode toggle and the picker follow what can be written to, not what
      # is connected.
      |> assign(:targets, Calendar.writable_integrations(assigns.integrations))

    ~H"""
    <.modal
      id="create-event-modal"
      show={true}
      on_cancel={JS.push("close_create_form", target: @myself)}
      size={:medium}
    >
      <:header>
        <FormParts.title_input
          id="create-event-title"
          name="title"
          value={@creating_event.title}
          placeholder={
            if @meeting_mode,
              do: dgettext("dashboard_calendar_events", "Meeting title"),
              else: dgettext("dashboard_calendar_events", "Event title")
          }
          required
          phx-mounted={JS.focus()}
          phx-blur="update_create_title"
          phx-target={@myself}
        />
      </:header>

      <%!-- Mode toggle: a bare provider event vs an ad-hoc Tymeslot meeting.
            Hidden when no calendar is connected — the form is then fixed to
            meeting mode, the only kind that can exist without one. --%>
      <:subheader :if={@targets != [] and @show_mode_toggle}>
        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <div
            class="inline-flex shrink-0 rounded-token-lg border border-neutral-300 dark:border-twilight-indigo-700 p-1 gap-1"
            role="tablist"
            aria-label={dgettext("dashboard_calendar_events", "What to create")}
          >
            <button
              type="button"
              role="tab"
              aria-selected={to_string(!@meeting_mode)}
              phx-click="set_create_mode"
              phx-value-mode="event"
              phx-target={@myself}
              class={mode_tab_class(!@meeting_mode)}
            >
              {dgettext("dashboard_calendar_events", "Event")}
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={to_string(@meeting_mode)}
              phx-click="set_create_mode"
              phx-value-mode="meeting"
              phx-target={@myself}
              data-testid="create-mode-meeting"
              class={mode_tab_class(@meeting_mode)}
            >
              {dgettext("dashboard_calendar_events", "Meeting with a guest")}
            </button>
          </div>
          <p
            :if={@meeting_mode}
            class="flex-1 min-w-[12rem] text-token-sm leading-snug text-neutral-500 dark:text-twilight-indigo-300"
          >
            {dgettext(
              "dashboard_calendar_events",
              "Books the slot, emails the guest an invitation, and adds it to your calendar."
            )}
          </p>
        </div>
      </:subheader>

      <div class="space-y-6 quiet-placeholders">
        <%!-- The guest (meeting mode only) comes first: it is what the dialog
              is for, and the time follows from them. --%>
        <div :if={@meeting_mode} class="space-y-4">
          <div>
            <FormParts.section_label for={
              if @contacts_allowed,
                do: "create-meeting-contact-picker",
                else: "create-meeting-guest-name"
            }>
              {dgettext("dashboard_calendar_events", "Guest")}
            </FormParts.section_label>
            <ContactPicker.contact_picker
              :if={@contacts_allowed}
              id="create-meeting-contact-picker"
              contacts={@contact_picker_results}
              query={@contact_picker_query}
              open={@contact_picker_open}
              target={@myself}
              query_event="guest_contact_query"
              select_event="select_guest_contact"
              close_event="close_guest_contact_picker"
              icon="hero-magnifying-glass"
              placeholder={
                dgettext("dashboard_calendar_events", "Search your contacts, or fill in below")
              }
            />
          </div>

          <div class="grid gap-4 sm:grid-cols-2">
            <div>
              <FormParts.field_label for="create-meeting-guest-name" required>
                {dgettext("dashboard_calendar_events", "Guest name")}
              </FormParts.field_label>
              <.input
                type="text"
                name="guest_name"
                value={@creating_event[:guest_name] || ""}
                placeholder={dgettext("dashboard_calendar_events", "Ada Lovelace")}
                id="create-meeting-guest-name"
                phx-blur="update_create_guest_name"
                phx-target={@myself}
              />
            </div>
            <div>
              <FormParts.field_label for="create-meeting-guest-email" required>
                {dgettext("dashboard_calendar_events", "Guest email")}
              </FormParts.field_label>
              <.input
                type="email"
                name="guest_email"
                value={@creating_event[:guest_email] || ""}
                placeholder="guest@example.com"
                id="create-meeting-guest-email"
                phx-blur="update_create_guest_email"
                phx-target={@myself}
              />
            </div>
          </div>

          <%!-- Further guests and the language every email about the meeting
                is written in. A bare provider event has its own attendee list
                further down, and no Tymeslot email to translate. --%>
          <div>
            <FormParts.field_label for="create-guest-email-input">
              {dgettext("dashboard_calendar_events", "More guests (optional)")}
            </FormParts.field_label>
            <div :if={@creating_event[:guest_emails] != []} class="flex flex-wrap gap-1.5 mb-2">
              <span
                :for={email <- @creating_event[:guest_emails] || []}
                class="inline-flex items-center gap-1 pl-2.5 pr-1 py-0.5 rounded-full bg-primary-50 dark:bg-primary-950/40 border border-primary-200 dark:border-primary-700 text-token-xs text-primary-800 dark:text-primary-300"
              >
                {email}
                <button
                  type="button"
                  phx-click="remove_create_guest"
                  phx-value-email={email}
                  phx-target={@myself}
                  class="w-4 h-4 rounded-full hover:bg-primary-200 flex items-center justify-center transition-colors"
                  aria-label={dgettext("dashboard_calendar_events", "Remove %{email}", email: email)}
                >
                  <.icon name="hero-x-mark" class="w-2.5 h-2.5" />
                </button>
              </span>
            </div>
            <form
              :if={length(@creating_event[:guest_emails] || []) < Guests.max_guests()}
              id="create-add-guest-form"
              phx-submit="add_create_guest"
              phx-target={@myself}
              class="flex items-start gap-2"
            >
              <.input
                type="email"
                id="create-guest-email-input"
                name="email"
                value={@creating_event[:guest_email_input] || ""}
                phx-change="update_create_guest_input"
                phx-target={@myself}
                placeholder="colleague@example.com"
                class="flex-1 min-w-0"
              />
              <.action_button type="submit" variant={:secondary} class="shrink-0">
                {dgettext("dashboard_calendar_events", "Add")}
              </.action_button>
            </form>
            <FormParts.hint>
              {dgettext(
                "dashboard_calendar_events",
                "Each one is invited by email and can accept or decline."
              )}
            </FormParts.hint>
          </div>

          <div>
            <p
              id="create-meeting-locale-label"
              class="mb-1.5 text-token-sm text-neutral-600 dark:text-twilight-indigo-200"
            >
              {dgettext("dashboard_calendar_events", "Language of the invitation")}
            </p>
            <div
              id="create-meeting-locale"
              role="group"
              aria-labelledby="create-meeting-locale-label"
              class="inline-flex flex-wrap items-center p-1 bg-white dark:bg-twilight-indigo-900 border-2 border-neutral-100 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1 max-w-full"
            >
              <.locale_button
                :for={locale <- Locales.supported()}
                locale={locale}
                active={@creating_event[:locale] == locale.code}
                phx-click="update_create_locale"
                phx-value-locale={locale.code}
                phx-target={@myself}
              />
            </div>
            <FormParts.hint>
              {dgettext(
                "dashboard_calendar_events",
                "The language every email about this meeting is written in, for the guest and anyone else invited."
              )}
            </FormParts.hint>
          </div>

          <%!-- Note to the guest: hidden behind a button so the form stays
                short for the meetings that need none. --%>
          <div>
            <button
              :if={!@creating_event[:note_open]}
              type="button"
              phx-click="toggle_create_note"
              phx-target={@myself}
              data-testid="create-meeting-add-note"
              class="inline-flex items-center gap-1.5 text-token-sm font-semibold text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300"
            >
              <.icon name="hero-plus-mini" class="w-4 h-4" />
              {dgettext("dashboard_calendar_events", "Add a note for the guest")}
            </button>
            <div :if={@creating_event[:note_open]}>
              <FormParts.field_label for="create-meeting-note">
                {dgettext("dashboard_calendar_events", "Note to the guest")}
              </FormParts.field_label>
              <.input
                type="textarea"
                name="organizer_note"
                value={@creating_event[:organizer_note] || ""}
                placeholder={
                  dgettext("dashboard_calendar_events", "An agenda, or anything to bring or prepare")
                }
                id="create-meeting-note"
                rows={3}
                maxlength={MeetingSchema.organizer_note_max_length()}
                phx-mounted={JS.focus()}
                phx-blur="update_create_note"
                phx-target={@myself}
              />
              <div class="mt-1.5 flex items-center justify-between gap-3">
                <FormParts.hint class="mt-0!">
                  {dgettext(
                    "dashboard_calendar_events",
                    "Included in the invitation and on the calendar entry."
                  )}
                </FormParts.hint>
                <button
                  type="button"
                  phx-click="toggle_create_note"
                  phx-target={@myself}
                  class="shrink-0 text-token-xs font-medium text-neutral-500 hover:text-neutral-700 dark:text-twilight-indigo-300 dark:hover:text-twilight-indigo-100"
                >
                  {dgettext("dashboard_calendar_events", "Remove note")}
                </button>
              </div>
            </div>
          </div>
        </div>

        <FormParts.divider :if={@meeting_mode} />

        <div class="space-y-3">
          <FormParts.date_time_range
            id_prefix="create-event"
            form_id="create-event-time-form"
            event="update_create_time"
            target={@myself}
            start_date={@creating_event.date}
            start_time={
              EditWorkflow.format_time_value(@creating_event.start_hour, @creating_event.start_minute)
            }
            end_date={@creating_event.end_date}
            end_time={
              EditWorkflow.format_time_value(@creating_event.end_hour, @creating_event.end_minute)
            }
            all_day={@creating_event[:all_day] || false}
          />
          <div class={[
            "flex items-center gap-4",
            if(@meeting_mode, do: "justify-end", else: "justify-between")
          ]}>
            <div :if={!@meeting_mode} class="flex items-center gap-3">
              <StatusSwitch.status_switch
                id="create-event-all-day"
                checked={@creating_event[:all_day] || false}
                on_change="toggle_create_all_day"
                target={@myself}
                size={:small}
                aria_label={dgettext("dashboard_calendar_events", "All day")}
              />
              <span class="text-token-sm font-medium text-neutral-700 dark:text-twilight-indigo-100">
                {dgettext("dashboard_calendar_events", "All day")}
              </span>
            </div>
            <FormParts.time_zone_note
              :if={!@creating_event[:all_day]}
              abbr={Helpers.tz_abbr(@user_timezone)}
            />
          </div>
        </div>

        <FormParts.divider :if={!@meeting_mode} />

        <%!-- Video is offered for a plain event as much as a meeting, and
              before attendees are added, so an event can be created with a
              room in one step. --%>
        <div
          :if={@targets != [] or @video_integrations != []}
          class="grid gap-4 sm:grid-cols-2"
        >
          <div :if={@targets != []}>
            <FormParts.section_label for="create-event-calendar">
              {dgettext("dashboard_calendar_events", "Calendar")}
            </FormParts.section_label>
            <CalendarPicker.calendar_picker
              id="create-event-calendar"
              integrations={@integrations}
              integration_colors={@integration_colors}
              selected_integration_id={@creating_event.integration_id}
              selected_calendar_id={@creating_event[:calendar_id]}
              myself={@myself}
              event_name="update_create_integration"
            />
          </div>
          <div :if={@video_integrations != []}>
            <FormParts.section_label for="create-event-video">
              {dgettext("dashboard_calendar_events", "Video")}
            </FormParts.section_label>
            <VideoPicker.video_picker
              id="create-event-video"
              video_integrations={@video_integrations}
              selected_id={@creating_event[:video_integration_id]}
              target={@myself}
              phx_event="update_create_video"
            />
          </div>
        </div>

        <%!-- Reminders, in both modes: synced to the calendar as a VALARM, and
              for a meeting also folded into the reminder email Tymeslot already
              sends (see `Tymeslot.Integrations.Calendar.CalendarEventBuilder`).
              A meeting doesn't repeat. --%>
        <div>
          <div class="grid gap-4 sm:grid-cols-2">
            <RecurrenceEditor.recurrence_editor
              :if={!@meeting_mode}
              recurrence_rule={@creating_event[:recurrence_rule]}
              timezone={@user_timezone}
              myself={@myself}
              change_event="update_create_recurrence"
            />
            <RemindersEditor.reminders_editor
              reminders={@creating_event[:reminders] || []}
              myself={@myself}
              add_event="add_create_reminder"
              remove_event="remove_create_reminder"
            />
          </div>
          <RemindersEditor.hint :if={!@meeting_mode} />
        </div>

        <%!-- Attendees of a plain event, invited by the calendar provider. --%>
        <div :if={!@meeting_mode}>
          <FormParts.section_label for="create-attendee-email" optional>
            {dgettext("dashboard_calendar_events", "Attendees")}
          </FormParts.section_label>
          <div :if={@creating_event[:attendees] != []} class="flex flex-wrap gap-1.5 mb-2">
            <span
              :for={email <- @creating_event[:attendees] || []}
              class="inline-flex items-center gap-1 pl-2.5 pr-1 py-0.5 rounded-full bg-amber-50 dark:bg-amber-950/40 border border-dashed border-amber-300 dark:border-amber-700 text-token-xs text-amber-800 dark:text-amber-300"
            >
              {email}
              <button
                type="button"
                phx-click="remove_create_attendee"
                phx-value-email={email}
                phx-target={@myself}
                class="w-4 h-4 rounded-full hover:bg-amber-200 flex items-center justify-center transition-colors"
                aria-label={dgettext("dashboard_calendar_events", "Remove %{email}", email: email)}
              >
                <.icon name="hero-x-mark" class="w-2.5 h-2.5" />
              </button>
            </span>
          </div>
          <form
            id="create-add-attendee-form"
            phx-submit="add_create_attendee"
            phx-target={@myself}
            class="flex items-start gap-2"
          >
            <.input
              type="email"
              id="create-attendee-email"
              name="email"
              value={@creating_event[:attendee_input] || ""}
              phx-change="update_create_attendee_input"
              phx-target={@myself}
              placeholder="attendee@example.com"
              class="flex-1 min-w-0"
            />
            <.action_button type="submit" variant={:secondary} class="shrink-0">
              {dgettext("dashboard_calendar_events", "Add")}
            </.action_button>
          </form>
          <FormParts.hint>
            {dgettext(
              "dashboard_calendar_events",
              "Invitations will be sent when you create the event."
            )}
          </FormParts.hint>
        </div>
      </div>

      <:footer>
        <div class="flex gap-2">
          <.action_button
            variant={:secondary}
            disabled={@saving}
            phx-click={JS.push("close_create_form", target: @myself)}
          >
            {dgettext("dashboard_calendar_events", "Cancel")}
          </.action_button>
          <.loading_button
            variant={:primary}
            loading={@saving}
            loading_text={
              if @meeting_mode,
                do: dgettext("dashboard_calendar_events", "Sending..."),
                else: dgettext("dashboard_calendar_events", "Creating...")
            }
            phx-click="save_event"
            phx-target={@myself}
          >
            {if @meeting_mode,
              do: dgettext("dashboard_calendar_events", "Send invitation"),
              else: dgettext("dashboard_calendar_events", "Create")}
          </.loading_button>
        </div>
      </:footer>
    </.modal>
    """
  end

  defp mode_tab_class(true),
    do:
      "px-4 py-1.5 rounded-token-md text-token-sm font-semibold bg-primary-600 text-white transition-colors"

  defp mode_tab_class(false),
    do:
      "px-4 py-1.5 rounded-token-md text-token-sm font-semibold text-neutral-600 dark:text-neutral-200 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 transition-colors"
end
