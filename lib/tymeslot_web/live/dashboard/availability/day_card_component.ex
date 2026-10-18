defmodule TymeslotWeb.Dashboard.Availability.DayCardComponent do
  @moduledoc """
  One row per weekday in the availability editor.

  Seven days share this surface, so each one is a single line: toggle, name,
  the two hour selects, the cap on that day's booked meeting time, and its
  breaks as inline chips. The bulk actions that
  used to sit in a per-day footer (copy to other days, clear the day) live in a
  small menu instead, because they are occasional and were costing every day a
  permanent two-button bar.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Availability.Window
  alias Tymeslot.Utils.DateTimeUtils
  alias Tymeslot.Validation.Constraints
  alias TymeslotWeb.Components.Shared.TimeOptions
  alias TymeslotWeb.Components.UI.StatusSwitch
  alias TymeslotWeb.Dashboard.Availability.ListComponent.BreakHelpers
  alias TymeslotWeb.Live.Shared.FormValidationHelpers
  alias TymeslotWeb.Themes.Shared.LocalizationHelpers

  attr :day_availability, :map, required: true
  attr :day_name, :string, required: true
  attr :break_duration_presets, :list, required: true
  attr :form_errors, :map, required: true
  attr :hours_errors, :map, default: %{}

  attr :refused_hours, :map,
    default: %{},
    doc: "per day, the start and end last picked and refused, shown until the day saves"

  attr :show_add_break_form, :any, required: true
  attr :open_menu_day, :any, required: true
  attr :time_format, :string, required: true
  attr :myself, :any, required: true

  @spec day_card(map()) :: Phoenix.LiveView.Rendered.t()
  def day_card(assigns) do
    assigns =
      assigns
      |> assign(:day, assigns.day_availability.day_of_week)
      |> assign(:breaks, breaks_of(assigns.day_availability))
      |> assign(:hours_errors_for_day, hours_errors_for(assigns))
      |> assign_hours_inputs()
      |> assign(:break_times, break_times(assigns.day_availability, assigns.time_format))

    ~H"""
    <div class={[
      "card-glass rounded-token-xl p-0! transition-colors duration-200",
      if(@day_availability.is_available, do: "card-glass-available", else: "card-glass-unavailable")
    ]}>
      <div class="flex flex-wrap items-center gap-x-4 gap-y-3 px-4 py-3">
        <StatusSwitch.status_switch
          id={"day-available-toggle-#{@day}"}
          checked={@day_availability.is_available == true}
          on_change="toggle_day_available"
          target={@myself}
          show_icon={false}
          aria_label={toggle_label(@day_availability.is_available, @day_name)}
          class="shrink-0"
          phx-value-day={@day}
        />

        <span class={[
          "w-24 shrink-0 font-bold text-token-sm",
          if(@day_availability.is_available,
            do: "text-neutral-900 dark:text-neutral-50",
            else: "text-neutral-500 dark:text-twilight-indigo-300"
          )
        ]}>
          {@day_name}
        </span>

        <%= if @day_availability.is_available do %>
          <form
            id={"day-hours-form-#{@day}"}
            phx-change="update_day_hours"
            phx-target={@myself}
            phx-debounce="500"
            class={
              [
                "day-hours-inline flex items-center gap-2 shrink-0",
                # On a phone the two selects share the row instead of pushing
                # the end time past the card's edge.
                "max-sm:w-full max-sm:shrink max-sm:min-w-0",
                "max-sm:[&>div]:min-w-0 max-sm:[&>div]:flex-1 max-sm:[&_.input]:w-full!"
              ]
            }
          >
            <input type="hidden" name="day" value={@day} />
            <.input
              type="select"
              name="start"
              options={TimeOptions.time_options(@time_format)}
              value={@start_value}
              aria-label={dgettext("dashboard_availability", "Start Time")}
            />
            <span class="text-neutral-400">–</span>
            <.input
              type="select"
              name="end"
              options={@end_options}
              value={@end_value}
              prompt={is_nil(@end_value) && dgettext("dashboard_availability", "End")}
              aria-label={dgettext("dashboard_availability", "End Time")}
              aria-describedby={hours_describedby(@day, @day_availability, @hours_errors_for_day)}
            />
          </form>
          <span
            :if={runs_past_midnight?(@day_availability)}
            id={"day-end-hint-#{@day}"}
            class="text-token-xs text-neutral-500 shrink-0 dark:text-twilight-indigo-300"
          >
            {dgettext("dashboard_availability", "Ends the next day")}
          </span>

          <form
            id={"day-max-minutes-form-#{@day}"}
            phx-change="update_day_max_minutes"
            phx-target={@myself}
            class="shrink-0"
          >
            <input type="hidden" name="day" value={@day} />
            <.input
              type="select"
              name="max_booked_minutes"
              prompt={dgettext("dashboard_availability", "No time limit")}
              options={max_booked_minutes_options()}
              value={@day_availability.max_booked_minutes}
              aria-label={max_minutes_label(@day_name)}
            />
          </form>

          <div class="flex flex-wrap items-center gap-2 grow">
            <span
              :for={break <- @breaks}
              class="inline-flex items-center gap-2 rounded-token-lg bg-neutral-50 dark:bg-twilight-indigo-900/60 border border-neutral-300 dark:border-neutral-600 px-2 py-1 text-token-xs font-bold text-neutral-600 dark:text-neutral-300"
            >
              {break.label || dgettext("dashboard_availability", "Break")}
              <span class="text-primary-600 font-medium">
                {BreakHelpers.break_time_label(@day_availability, break, @time_format)}
              </span>
              <.icon_button
                icon="hero-x-mark"
                variant={:danger}
                size={:sm}
                label={dgettext("dashboard_availability", "Delete Break")}
                phx-click="show_delete_break_modal"
                phx-value-break_id={break.id}
                phx-target={@myself}
              />
            </span>

            <.action_button
              :if={@show_add_break_form != @day}
              variant={:ghost}
              size={:sm}
              icon="hero-plus"
              phx-click="show_add_break_form"
              phx-value-day={@day}
              phx-target={@myself}
            >
              {dgettext("dashboard_availability", "Add Break")}
            </.action_button>
          </div>

          <.dropdown
            id={"day-actions-#{@day}"}
            open={@open_menu_day == @day}
            on_toggle="toggle_day_menu"
            on_close="close_day_menu"
            target={@myself}
            trigger_class="row-action-button row-action-button--icon-only row-action-button--neutral shrink-0"
            trigger_attrs={[{"phx-value-day", @day}]}
            class="bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-lg py-1 w-56"
            aria-label={day_menu_label(@day_name)}
          >
            <:trigger>
              <.icon name="hero-pencil-square" class="w-5 h-5" />
            </:trigger>
            <:panel>
              <.dropdown_item
                label={dgettext("dashboard_availability", "Apply to All Days")}
                icon="hero-arrows-right-left"
                phx-click="copy_to_days"
                phx-value-from_day={@day}
                phx-value-to_days="1,2,3,4,5,6,7"
                phx-target={@myself}
              />
              <.dropdown_item
                label={dgettext("dashboard_availability", "Apply to Workdays")}
                icon="hero-arrows-right-left"
                phx-click="copy_to_days"
                phx-value-from_day={@day}
                phx-value-to_days="1,2,3,4,5"
                phx-target={@myself}
              />
              <.dropdown_divider />
              <.dropdown_item
                label={dgettext("dashboard_availability", "Clear Day")}
                icon="hero-trash"
                danger
                phx-click="show_clear_day_modal"
                phx-value-day={@day}
                phx-target={@myself}
              />
            </:panel>
          </.dropdown>
        <% else %>
          <span class="availability-status text-token-sm">
            {dgettext("dashboard_availability", "Unavailable")}
          </span>
        <% end %>
      </div>

      <p
        :for={message <- @hours_errors_for_day}
        id={"day-hours-errors-#{@day}"}
        role="alert"
        class="px-4 pb-3 text-token-sm text-red-600"
      >
        {message}
      </p>

      <%!-- The add-break form drops below its day rather than inline, so the
      row keeps its height until the user asks for it. Fields are top-aligned:
      bottom-aligning them lets a validation message under one field push every
      other field out of line as it appears. --%>
      <form
        :if={@show_add_break_form == @day}
        id={"add-break-form-#{@day}"}
        phx-submit="add_break"
        phx-change="validate_break"
        phx-target={@myself}
        class="flex flex-wrap items-start gap-3 rounded-b-token-xl border-t-2 border-neutral-300 bg-neutral-50/40 px-4 py-3"
        novalidate
      >
        <input type="hidden" name="day" value={@day} />
        <div class="w-40">
          <.input
            name="label"
            label={dgettext("dashboard_availability", "Label")}
            placeholder={dgettext("dashboard_availability", "e.g. Lunch")}
            maxlength={Constraints.break_label_max_length()}
            errors={FormValidationHelpers.field_errors(@form_errors, :label)}
          />
        </div>
        <div class="w-32">
          <.input
            type="select"
            name="start"
            label={dgettext("dashboard_availability", "From")}
            required
            prompt={dgettext("dashboard_availability", "Start")}
            options={@break_times.start}
            errors={FormValidationHelpers.field_errors(@form_errors, :start_time)}
          />
        </div>
        <div class="w-32">
          <.input
            type="select"
            name="end"
            label={dgettext("dashboard_availability", "Until")}
            required
            prompt={dgettext("dashboard_availability", "End")}
            options={@break_times.end}
            errors={FormValidationHelpers.field_errors(@form_errors, :end_time)}
          />
        </div>
        <div>
          <%!-- Empty label of the same shape as the fields', so the buttons sit
          on the input line without hard-coding the label's height. --%>
          <span class="label" aria-hidden="true">&nbsp;</span>
          <div class="flex items-center gap-2">
            <.action_button type="submit">
              {dgettext("dashboard_availability", "Add")}
            </.action_button>
            <.icon_button
              icon="hero-x-mark"
              label={dgettext("dashboard_availability", "Cancel")}
              phx-click="hide_add_break_form"
              phx-target={@myself}
            />
          </div>
        </div>
      </form>
    </div>
    """
  end

  defp breaks_of(%{breaks: breaks}) when is_list(breaks), do: breaks
  defp breaks_of(_day_availability), do: []

  # A break lives inside its day, so the pickers only offer that window: the
  # "from" list stops one slot short of the day's end and the "until" list
  # starts one slot after its beginning, which leaves ordering as the only way
  # left to pick an invalid pair. Hours that run past midnight are walked
  # through it, in order.
  defp break_times(%{start_time: %Time{}, end_time: %Time{}} = day_availability, time_format) do
    slots = TimeOptions.window_options(day_availability, time_format)

    %{start: Enum.drop(slots, -1), end: Enum.drop(slots, 1)}
  end

  defp break_times(_day_availability, _time_format), do: %{start: [], end: []}

  defp max_booked_minutes_options do
    Enum.map(Constraints.daily_booked_minutes_values(), fn minutes ->
      {dgettext("dashboard_availability", "Max %{duration} of meetings",
         duration: LocalizationHelpers.format_duration(minutes)
       ), minutes}
    end)
  end

  defp max_minutes_label(day_name),
    do: dgettext("dashboard_availability", "Maximum meeting time on %{day}", day: day_name)

  defp hours_errors_for(%{hours_errors: errors, day_availability: %{day_of_week: day}}),
    do: errors |> Map.get(day, %{}) |> Map.values() |> Enum.uniq()

  defp hours_describedby(day, day_availability, errors) do
    ids =
      Enum.reject(
        [
          if(runs_past_midnight?(day_availability), do: "day-end-hint-#{day}"),
          if(errors != [], do: "day-hours-errors-#{day}")
        ],
        &is_nil/1
      )

    if ids == [], do: nil, else: Enum.join(ids, " ")
  end

  defp end_value(day_availability),
    do: Window.format_end(day_availability.end_time, day_availability.ends_next_day)

  # The hours selects show the day's saved hours, or the times last picked and
  # refused. End options always follow the start shown. A refused end that is
  # not among them (an end before the new start, without its "(+1)") leaves
  # the end select blank rather than showing a time that no longer fits, so
  # the error beneath asks for a pick the select can still offer.
  defp assign_hours_inputs(%{day: day, day_availability: day_availability} = assigns) do
    refused = Map.get(assigns.refused_hours, day, %{})
    saved_start = BreakHelpers.format_time(day_availability.start_time)
    start_value = refused["start"] || saved_start

    start_time =
      case DateTimeUtils.parse_hhmm(start_value) do
        {:ok, time} -> time
        {:error, _reason} -> day_availability.start_time
      end

    wanted_end = refused["end"] || end_value(day_availability)
    end_options = TimeOptions.end_options(start_time, assigns.time_format, wanted_end)

    assign(assigns,
      start_value: start_value,
      end_options: end_options,
      end_value: if(Enum.any?(end_options, &(elem(&1, 1) == wanted_end)), do: wanted_end)
    )
  end

  # Hours ending exactly at midnight already read clearly as "00:00 (+1)" in
  # the end select; the hint is for hours that carry on into the next day.
  defp runs_past_midnight?(%{ends_next_day: true, end_time: %Time{} = end_time}),
    do: Time.compare(end_time, ~T[00:00:00]) == :gt

  defp runs_past_midnight?(_day_availability), do: false

  defp toggle_label(true, day_name),
    do: dgettext("dashboard_availability", "Stop taking bookings on %{day}", day: day_name)

  defp toggle_label(false, day_name),
    do: dgettext("dashboard_availability", "Take bookings on %{day}", day: day_name)

  defp day_menu_label(day_name),
    do: dgettext("dashboard_availability", "More actions for %{day}", day: day_name)
end
