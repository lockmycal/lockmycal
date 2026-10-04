defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.RemindersEditor do
  @moduledoc """
  Reusable reminders editor for the calendar create/detail modals.

  A select of preset lead times with a "+" button that adds the chosen one,
  and the reminders already set as removable tags under it. The lead times
  offered are exactly `Shared.reminder_minutes_presets/0`, the list
  `Shared.parse_reminder/1` validates an added reminder against, labelled
  through `reminder_label/1`'s own `minutes_label/1`; there is no second copy
  of the values to fall out of step.

  An added reminder is a notification (`method: popup`): the form offers no
  choice of method. A reminder that is an email — set elsewhere, or before the
  choice went away — still shows as a tag and can be removed.

  Reminders are synced to the calendar provider, which fires the alert on the
  user's own devices — Tymeslot does not fire them itself. The line saying so
  belongs to the dialog (`hint/1`), which places it under its own layout.

  Add/remove actions dispatch `add_event` / `remove_event` back to the owning
  LiveComponent via `phx-target`, carrying `method` + `minutes` (add) or `index`
  (remove). The owner threads the canonical
  `%{method: :popup | :email, minutes_before: integer}` shape through its state.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Integrations.Calendar.Reminder
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.FormParts

  attr :reminders, :list, default: []
  attr :myself, :any, required: true
  attr :add_event, :string, required: true
  attr :remove_event, :string, required: true

  attr :read_only, :boolean,
    default: false,
    doc:
      "Leaves out the add control and lists the reminders only, e.g. an existing event's modal that only allows removing reminders."

  @spec reminders_editor(map()) :: Phoenix.LiveView.Rendered.t()
  def reminders_editor(assigns) do
    assigns = assign(assigns, :presets, presets())

    ~H"""
    <div>
      <FormParts.section_label for={if not @read_only, do: "add-reminder-minutes"}>
        {dgettext("dashboard_calendar_events", "Reminder")}
      </FormParts.section_label>
      <form
        :if={not @read_only}
        id="add-reminder-form"
        phx-submit={@add_event}
        phx-target={@myself}
        class="flex items-start gap-2"
      >
        <input type="hidden" name="method" value="popup" />
        <.input
          type="select"
          id="add-reminder-minutes"
          name="minutes"
          options={@presets}
          class="flex-1 min-w-0"
        />
        <.action_button
          type="submit"
          variant={:secondary}
          class="shrink-0 px-3.5!"
          aria-label={dgettext("dashboard_calendar_events", "Add reminder")}
          title={dgettext("dashboard_calendar_events", "Add reminder")}
        >
          <.icon name="hero-plus" class="w-5 h-5" />
        </.action_button>
      </form>
      <p
        :if={@read_only and @reminders == []}
        class="text-token-sm text-neutral-500 dark:text-twilight-indigo-300"
      >
        {dgettext("dashboard_calendar_events", "None")}
      </p>
      <div :if={@reminders != []} class={["flex flex-wrap gap-1.5", not @read_only && "mt-2"]}>
        <span
          :for={{reminder, index} <- Enum.with_index(@reminders)}
          class="inline-flex items-center gap-1 pl-2.5 pr-1 py-0.5 rounded-full bg-primary-50 dark:bg-primary-950/40 border border-primary-200 dark:border-primary-700 text-token-xs text-primary-800 dark:text-primary-300"
        >
          {reminder_label(reminder)}
          <button
            type="button"
            phx-click={@remove_event}
            phx-value-index={index}
            phx-target={@myself}
            class="w-4 h-4 rounded-full hover:bg-red-100 flex items-center justify-center transition-colors"
            aria-label={
              dgettext("dashboard_calendar_events", "Remove reminder %{label}",
                label: reminder_label(reminder)
              )
            }
          >
            <.icon name="hero-x-mark-micro" class="w-2.5 h-2.5" />
          </button>
        </span>
      </div>
    </div>
    """
  end

  @doc "The line explaining where reminders go off, for the dialog to place."
  @spec hint(map()) :: Phoenix.LiveView.Rendered.t()
  def hint(assigns) do
    ~H"""
    <FormParts.hint>
      {dgettext(
        "dashboard_calendar_events",
        "Reminders are synced to your calendar so it can alert you on your own devices."
      )}
    </FormParts.hint>
    """
  end

  @doc """
  Returns a human-readable label for a reminder, e.g. "Notification 10 minutes before".

  Reads through `Reminder`, so a raw string-keyed reminder straight out of the
  JSONB cache column labels the same as a canonical atom-keyed one. Rendering is
  the last place that should fail on a shape: a mislabelled reminder is a far
  cheaper outcome than a crashed calendar.
  """
  @spec reminder_label(map()) :: String.t()
  def reminder_label(%{} = reminder) do
    dgettext("dashboard_calendar_events", "%{method} %{minutes}",
      method: method_label(Reminder.method(reminder)),
      minutes: minutes_label(Reminder.minutes_before(reminder))
    )
  end

  defp method_label(:email), do: dgettext("dashboard_calendar_events", "Email")
  defp method_label(_popup_or_other), do: dgettext("dashboard_calendar_events", "Notification")

  # A provider alarm whose trigger we could not parse reaches the cache without
  # a lead time. Say so rather than inventing one.
  defp minutes_label(minutes) when not is_integer(minutes),
    do: dgettext("dashboard_calendar_events", "before the event")

  defp minutes_label(1440), do: dgettext("dashboard_calendar_events", "1 day before")
  defp minutes_label(60), do: dgettext("dashboard_calendar_events", "1 hour before")

  defp minutes_label(minutes) when minutes >= 60 and rem(minutes, 60) == 0,
    do:
      dngettext(
        "dashboard_calendar_events",
        "%{count} hour before",
        "%{count} hours before",
        div(minutes, 60)
      )

  defp minutes_label(minutes),
    do:
      dngettext(
        "dashboard_calendar_events",
        "%{count} minute before",
        "%{count} minutes before",
        minutes
      )

  # Offer exactly the lead times `parse_reminder/1` accepts, labelled by the same
  # function that labels a saved reminder. A value added to the whitelist shows
  # up here with a label already; one removed stops being offered.
  defp presets do
    Enum.map(Shared.reminder_minutes_presets(), &{minutes_label(&1), &1})
  end
end
