defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.AttendeeEditor do
  @moduledoc """
  Attendee list and editor for the calendar event detail modal.

  Renders one of two faces depending on `editable`. In edit mode the invited
  attendees show as removable turquoise tags, attendees added but not yet sent
  show as amber dashed tags, and an email form appends to the pending set. In
  read-only mode it lists the first five attendees and summarises the rest.

  The two sets are deliberately distinct: an invited attendee has already had a
  calendar invitation sent on their behalf, so removing one dispatches
  `request_remove_attendee` for the owner to confirm, while a pending one has
  not been sent anything yet and is dropped outright with
  `remove_pending_attendee`. Add/remove and input events all dispatch back to
  the owning LiveComponent via `phx-target`.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.FormParts

  attr :editable, :boolean, default: false
  attr :attendees, :list, default: []
  attr :pending_attendees, :list, default: []
  attr :attendee_input, :string, default: ""
  attr :myself, :any, required: true

  attr :read_only, :boolean,
    default: false,
    doc:
      "Leaves out the add-attendee form and its hint, e.g. an existing event's modal that only allows removing attendees."

  @spec attendee_editor(map()) :: Phoenix.LiveView.Rendered.t()
  def attendee_editor(assigns) do
    ~H"""
    <div :if={(@editable and not @read_only) or @attendees != [] or @pending_attendees != []}>
      <FormParts.section_label
        for={if @editable and not @read_only, do: "edit-attendee-email"}
        optional={@editable and not @read_only}
      >
        {dgettext("dashboard_calendar_events", "Attendees")}
      </FormParts.section_label>
      <div>
        <%!-- Editable attendee tags --%>
        <div :if={@editable}>
          <div
            :if={@attendees != [] or @pending_attendees != []}
            class="flex flex-wrap gap-1.5 mb-2"
          >
            <%!-- Existing (invited) attendees: turquoise --%>
            <span
              :for={attendee <- @attendees}
              class="inline-flex items-center gap-1 pl-2.5 pr-1 py-0.5 rounded-token-full bg-primary-50 border border-primary-200 text-token-xs text-primary-800 dark:bg-primary-900/30"
            >
              {attendee.display_name || attendee.email}
              <button
                type="button"
                phx-click="request_remove_attendee"
                phx-value-email={attendee.email}
                phx-target={@myself}
                class="w-4 h-4 rounded-token-full hover:bg-red-100 flex items-center justify-center transition-colors"
                aria-label={
                  dgettext("dashboard_calendar_events", "Remove %{email}", email: attendee.email)
                }
              >
                <.icon name="hero-x-mark-micro" class="w-2.5 h-2.5" />
              </button>
            </span>
            <%!-- Pending (unsent) attendees: amber, dashed --%>
            <span
              :for={email <- @pending_attendees}
              class="inline-flex items-center gap-1 pl-2.5 pr-1 py-0.5 rounded-token-full bg-amber-50 border border-dashed border-amber-300 text-token-xs text-amber-800 dark:bg-amber-950/40 dark:text-amber-200"
            >
              {email}
              <button
                type="button"
                phx-click="remove_pending_attendee"
                phx-value-email={email}
                phx-target={@myself}
                class="w-4 h-4 rounded-token-full hover:bg-amber-200 flex items-center justify-center transition-colors"
                aria-label={dgettext("dashboard_calendar_events", "Remove %{email}", email: email)}
              >
                <.icon name="hero-x-mark-micro" class="w-2.5 h-2.5" />
              </button>
            </span>
          </div>
          <%!-- Only where attendees can be added: an empty read-only input would
               show its example address as if it were an attendee. --%>
          <form
            :if={not @read_only}
            id="event-add-attendee-form"
            phx-submit="add_event_attendee"
            phx-target={@myself}
            class="flex items-start gap-2"
          >
            <.input
              type="email"
              id="edit-attendee-email"
              name="email"
              value={@attendee_input}
              phx-change="update_attendee_input"
              phx-target={@myself}
              placeholder="attendee@example.com"
              class="flex-1 min-w-0"
            />
            <.action_button type="submit" variant={:secondary} class="shrink-0">
              {dgettext("dashboard_calendar_events", "Add")}
            </.action_button>
          </form>
          <FormParts.hint :if={not @read_only and @pending_attendees == []}>
            {dgettext(
              "dashboard_calendar_events",
              "Each person will receive an invitation from your calendar provider."
            )}
          </FormParts.hint>
        </div>
        <%!-- Read-only attendee display --%>
        <div :if={!@editable}>
          <div
            :for={attendee <- Enum.take(@attendees, 5)}
            class="text-token-sm text-neutral-700 dark:text-neutral-200 leading-snug"
          >
            {attendee.display_name || attendee.email}
            <span
              :if={attendee.display_name && attendee.email && attendee.display_name != attendee.email}
              class="text-token-xs text-neutral-400 ml-1 dark:text-twilight-indigo-300"
            >{attendee.email}</span>
          </div>
          <p
            :if={length(@attendees) > 5}
            class="text-token-xs text-neutral-400 mt-1 dark:text-twilight-indigo-300"
          >
            {dngettext(
              "dashboard_calendar_events",
              "+%{count} more",
              "+%{count} more",
              length(@attendees) - 5
            )}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
