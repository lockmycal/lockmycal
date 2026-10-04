defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.RecurrenceEditor do
  @moduledoc """
  Reusable "Repeat" control for the calendar create/detail modals.

  Renders a frequency selector (Does not repeat / Daily / Weekly / Monthly /
  Yearly). Choosing a repeating frequency reveals the recurrence detail row:
  an interval ("every N"), weekday toggles (weekly only), and an end condition
  (never / after N occurrences / on a date). A human-readable summary of the
  current rule is shown beneath the controls.

  Every control change dispatches `change_event` back to the owning
  LiveComponent via `phx-target`, carrying the raw form fields (`freq`,
  `interval`, `by_day[]`, `end_type`, `count`, `until`). The owner composes the
  canonical RRULE string from those fields via
  `Tymeslot.Integrations.Calendar.Recurrence.RRule.build/1` and threads it
  through its state — keeping this component stateless and free of RRULE logic.

  `recurrence_rule` is the current canonical RRULE string (or nil); it is parsed
  only to seed the control values for display. Parsing takes `timezone` because
  a timed rule's `UNTIL` is a UTC instant, and the date to put back in the date
  input is the one that instant falls on where the organiser is.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Integrations.Calendar.Recurrence.RRule
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.FormParts

  attr :recurrence_rule, :string, default: nil
  attr :timezone, :string, default: nil
  attr :myself, :any, required: true
  attr :change_event, :string, required: true

  attr :read_only, :boolean,
    default: false,
    doc: "Shows the rule's summary instead of the controls, e.g. an existing event's modal."

  @spec recurrence_editor(map()) :: Phoenix.LiveView.Rendered.t()
  def recurrence_editor(assigns) do
    parsed = RRule.parse(assigns.recurrence_rule || "", timezone: assigns.timezone)

    assigns =
      assigns
      |> assign(:parsed, parsed)
      |> assign(:freq, parsed[:freq])
      |> assign(:interval, parsed[:interval] || 1)
      |> assign(:by_day, parsed[:by_day] || [])
      |> assign(:end_type, end_type(parsed))
      |> assign(:count, parsed[:count] || Shared.default_recurrence_count())
      |> assign(:until, until_value(parsed[:until]))
      |> assign(:weekdays, weekdays())
      |> assign(:freq_options, freq_options())
      |> assign(:summary, summary(parsed))

    ~H"""
    <div>
      <FormParts.section_label for={if not @read_only, do: "recurrence-freq-#{@change_event}"}>
        {dgettext("dashboard_calendar_events", "Repeat")}
      </FormParts.section_label>
      <div>
        <%!-- Read-only: just what the rule says, not a form of disabled controls. --%>
        <p
          :if={@read_only}
          class="text-token-sm text-neutral-600 dark:text-neutral-300 leading-snug"
        >
          {@summary || dgettext("dashboard_calendar_events", "Does not repeat")}
        </p>
        <form
          :if={not @read_only}
          id={"recurrence-editor-form-#{@change_event}"}
          phx-change={@change_event}
          phx-target={@myself}
          class="space-y-2"
        >
          <.input
            type="select"
            id={"recurrence-freq-#{@change_event}"}
            name="freq"
            value={to_string(@freq)}
            options={Enum.map(@freq_options, fn {value, label} -> {label, value} end)}
          />

          <div :if={@freq != nil} class="space-y-2 pl-0.5">
            <div class="flex items-center gap-2">
              <label class="text-token-xs text-neutral-600 dark:text-twilight-indigo-200">{dgettext(
                "dashboard_calendar_events",
                "Every"
              )}</label>
              <input
                type="number"
                name="interval"
                min="1"
                max="999"
                value={@interval}
                class="w-16 rounded-md border-neutral-300 dark:border-twilight-indigo-700 dark:bg-twilight-indigo-900/60 text-token-xs text-neutral-700 dark:text-twilight-indigo-100 focus:border-primary-500 focus:ring-primary-500 py-1"
              />
              <span class="text-token-xs text-neutral-600 dark:text-twilight-indigo-200">{interval_unit(
                @freq
              )}</span>
            </div>

            <div :if={@freq == :weekly} class="flex flex-wrap gap-1">
              <label
                :for={{day, label} <- @weekdays}
                class={[
                  "px-2 py-1 rounded-md border text-token-xs transition-all select-none",
                  "cursor-pointer",
                  weekday_label_class(day in @by_day)
                ]}
              >
                <input
                  type="checkbox"
                  name="by_day[]"
                  value={day}
                  checked={day in @by_day}
                  class="sr-only"
                />
                {label}
              </label>
            </div>

            <div class="flex flex-wrap items-center gap-2">
              <select
                name="end_type"
                class="rounded-md border-neutral-300 dark:border-twilight-indigo-700 dark:bg-twilight-indigo-900/60 text-token-xs text-neutral-700 dark:text-twilight-indigo-100 focus:border-primary-500 focus:ring-primary-500 py-1"
              >
                <option value="never" selected={@end_type == "never"}>
                  {dgettext("dashboard_calendar_events", "Never ends")}
                </option>
                <option value="count" selected={@end_type == "count"}>
                  {dgettext("dashboard_calendar_events", "After")}
                </option>
                <option value="until" selected={@end_type == "until"}>
                  {dgettext("dashboard_calendar_events", "On date")}
                </option>
              </select>

              <div :if={@end_type == "count"} class="flex items-center gap-1.5">
                <input
                  type="number"
                  name="count"
                  min="1"
                  max="999"
                  value={@count}
                  class="w-16 rounded-md border-neutral-300 dark:border-twilight-indigo-700 dark:bg-twilight-indigo-900/60 text-token-xs text-neutral-700 dark:text-twilight-indigo-100 focus:border-primary-500 focus:ring-primary-500 py-1"
                />
                <span class="text-token-xs text-neutral-600 dark:text-twilight-indigo-200">{dngettext(
                  "dashboard_calendar_events",
                  "occurrence",
                  "occurrences",
                  @count
                )}</span>
              </div>

              <input
                :if={@end_type == "until"}
                type="date"
                name="until"
                value={@until}
                class="rounded-md border-neutral-300 dark:border-twilight-indigo-700 dark:bg-twilight-indigo-900/60 text-token-xs text-neutral-700 dark:text-twilight-indigo-100 focus:border-primary-500 focus:ring-primary-500 py-1"
              />
            </div>
          </div>
        </form>

        <p
          :if={not @read_only and @summary != nil}
          class="text-token-xs text-neutral-400 dark:text-twilight-indigo-300 mt-1.5"
        >
          {@summary}
        </p>
      </div>
    </div>
    """
  end

  # Weekday toggle border/background, with a hover treatment when not selected.
  defp weekday_label_class(true),
    do:
      "border-primary-400 bg-primary-50 dark:bg-primary-950/40 text-primary-800 dark:text-primary-300 font-semibold"

  defp weekday_label_class(false),
    do:
      "border-neutral-300 dark:border-twilight-indigo-700 text-neutral-600 dark:text-twilight-indigo-200 hover:border-neutral-300 dark:hover:border-twilight-indigo-600 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-900"

  @doc """
  Returns a human-readable summary of an RRULE option map, e.g.
  "Repeats weekly on Mon, Wed". Returns `nil` for a non-recurring rule.
  """
  @spec summary(map()) :: String.t() | nil
  def summary(%{freq: freq} = parsed) do
    [base_phrase(freq, parsed), by_day_phrase(parsed), end_phrase(parsed)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def summary(_parsed), do: nil

  defp base_phrase(freq, parsed) do
    interval = Map.get(parsed, :interval, 1)

    if interval > 1 do
      interval_phrase(freq, interval)
    else
      freq_adverb_phrase(freq)
    end
  end

  defp interval_phrase(:daily, interval),
    do:
      dngettext(
        "dashboard_calendar_events",
        "Repeats every %{count} day",
        "Repeats every %{count} days",
        interval
      )

  defp interval_phrase(:weekly, interval),
    do:
      dngettext(
        "dashboard_calendar_events",
        "Repeats every %{count} week",
        "Repeats every %{count} weeks",
        interval
      )

  defp interval_phrase(:monthly, interval),
    do:
      dngettext(
        "dashboard_calendar_events",
        "Repeats every %{count} month",
        "Repeats every %{count} months",
        interval
      )

  defp interval_phrase(:yearly, interval),
    do:
      dngettext(
        "dashboard_calendar_events",
        "Repeats every %{count} year",
        "Repeats every %{count} years",
        interval
      )

  defp freq_adverb_phrase(:daily), do: dgettext("dashboard_calendar_events", "Repeats daily")
  defp freq_adverb_phrase(:weekly), do: dgettext("dashboard_calendar_events", "Repeats weekly")
  defp freq_adverb_phrase(:monthly), do: dgettext("dashboard_calendar_events", "Repeats monthly")
  defp freq_adverb_phrase(:yearly), do: dgettext("dashboard_calendar_events", "Repeats yearly")

  defp by_day_phrase(%{freq: :weekly, by_day: [_first | _rest] = days}) do
    days_label = Enum.map_join(days, ", ", &weekday_label/1)
    dgettext("dashboard_calendar_events", "on %{days}", days: days_label)
  end

  defp by_day_phrase(_parsed), do: nil

  defp end_phrase(%{count: count}) when is_integer(count),
    do:
      dngettext(
        "dashboard_calendar_events",
        "for %{count} occurrence",
        "for %{count} occurrences",
        count
      )

  defp end_phrase(%{until: %Date{} = until}),
    do: dgettext("dashboard_calendar_events", "until %{date}", date: Date.to_iso8601(until))

  defp end_phrase(_parsed), do: nil

  defp weekday_label(day) do
    {_atom, label} = Enum.find(weekdays(), fn {atom, _label} -> atom == day end)
    label
  end

  defp end_type(%{count: count}) when is_integer(count), do: "count"
  defp end_type(%{until: %Date{}}), do: "until"
  defp end_type(_parsed), do: "never"

  defp until_value(%Date{} = date), do: Date.to_iso8601(date)
  defp until_value(_other), do: ""

  defp interval_unit(:daily), do: dgettext("dashboard_calendar_events", "day(s)")
  defp interval_unit(:weekly), do: dgettext("dashboard_calendar_events", "week(s)")
  defp interval_unit(:monthly), do: dgettext("dashboard_calendar_events", "month(s)")
  defp interval_unit(:yearly), do: dgettext("dashboard_calendar_events", "year(s)")
  defp interval_unit(_other), do: ""

  defp weekdays do
    [
      {:mo, dgettext("dashboard_calendar_events", "Mon")},
      {:tu, dgettext("dashboard_calendar_events", "Tue")},
      {:we, dgettext("dashboard_calendar_events", "Wed")},
      {:th, dgettext("dashboard_calendar_events", "Thu")},
      {:fr, dgettext("dashboard_calendar_events", "Fri")},
      {:sa, dgettext("dashboard_calendar_events", "Sat")},
      {:su, dgettext("dashboard_calendar_events", "Sun")}
    ]
  end

  defp freq_options do
    [
      {"", dgettext("dashboard_calendar_events", "Does not repeat")},
      {"daily", dgettext("dashboard_calendar_events", "Daily")},
      {"weekly", dgettext("dashboard_calendar_events", "Weekly")},
      {"monthly", dgettext("dashboard_calendar_events", "Monthly")},
      {"yearly", dgettext("dashboard_calendar_events", "Yearly")}
    ]
  end
end
