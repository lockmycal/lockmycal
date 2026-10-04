defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.FormParts do
  @moduledoc """
  The building blocks the calendar's event dialogs share — the new-event /
  new-meeting dialog (`CreateEventModal`), an event's detail
  (`EventDetailModal`) and a booking's detail (`BookingDetailModal`) — so the
  three read as one form: an editable name in the header, small uppercase
  section labels, plain field labels, hints, and the start/end date and time
  fields.

  The inputs themselves are `CoreComponents.input/1`, the app's standard
  field, rather than a style of their own.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  @doc "Small uppercase label heading a section (Calendar, Video, Reminder, ...)."
  attr :for, :string, default: nil
  attr :optional, :boolean, default: false, doc: "appends a lowercase “(optional)”"
  attr :class, :string, default: nil
  slot :inner_block, required: true

  @spec section_label(map()) :: Phoenix.LiveView.Rendered.t()
  def section_label(assigns) do
    ~H"""
    <label
      for={@for}
      class={[
        "block mb-2 text-token-xs font-semibold uppercase tracking-wider text-neutral-500 dark:text-twilight-indigo-300",
        @class
      ]}
    >
      {render_slot(@inner_block)}
      <span :if={@optional} class="normal-case tracking-normal font-normal">
        {dgettext("dashboard_calendar_events", "(optional)")}
      </span>
    </label>
    """
  end

  @doc "Plain label of a single field (Start, Guest name, ...)."
  attr :for, :string, default: nil
  attr :required, :boolean, default: false
  slot :inner_block, required: true

  @spec field_label(map()) :: Phoenix.LiveView.Rendered.t()
  def field_label(assigns) do
    ~H"""
    <label
      for={@for}
      class="block mb-1.5 text-token-sm text-neutral-600 dark:text-twilight-indigo-200"
    >
      {render_slot(@inner_block)}<span :if={@required} class="text-red-500 ml-0.5">*</span>
    </label>
    """
  end

  @doc "Small explanatory line under a field."
  attr :class, :string, default: nil
  slot :inner_block, required: true

  @spec hint(map()) :: Phoenix.LiveView.Rendered.t()
  def hint(assigns) do
    ~H"""
    <p class={["mt-1.5 text-token-xs text-neutral-400 dark:text-twilight-indigo-300", @class]}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  The dialog's name as an input in its header, behind a pencil, so it reads as
  the title and is edited in place. Every extra attribute (`phx-blur`,
  `phx-target`, ...) is passed to the input.
  """
  attr :id, :string, required: true
  attr :name, :string, default: "value"
  attr :value, :string, default: ""
  attr :placeholder, :string, required: true
  attr :required, :boolean, default: false
  attr :rest, :global, include: ~w(phx-debounce)

  @spec title_input(map()) :: Phoenix.LiveView.Rendered.t()
  def title_input(assigns) do
    ~H"""
    <span class="flex items-center gap-3 min-w-0">
      <.icon
        name="hero-pencil"
        class="w-5 h-5 shrink-0 text-neutral-400 dark:text-twilight-indigo-300"
      />
      <%!-- A heading-sized input: no box, just an underline on hover/focus. --%>
      <input
        type="text"
        id={@id}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        aria-label={@placeholder}
        aria-required={to_string(@required)}
        autocomplete="off"
        class="w-full min-w-0 bg-transparent border-0 border-b-2 border-transparent hover:border-neutral-300 dark:hover:border-twilight-indigo-600 focus:border-primary-500 focus:ring-0 focus-visible:ring-0! px-0 py-0.5 text-token-2xl font-bold text-neutral-900 dark:text-neutral-50 placeholder:font-normal placeholder:text-neutral-300 dark:placeholder:text-neutral-600 transition-colors"
        {@rest}
      />
      <span :if={@required} class="text-token-2xl font-bold text-red-500" aria-hidden="true">*</span>
    </span>
    """
  end

  @doc """
  Start and end, each a date field with a time field beside it, as a form that
  sends `event` on every change with `start-date`, `start-time`, `end-date` and
  `end-time` (the time fields left out for an all-day range).

  `id_prefix` names the form (`<prefix>-form`) and the fields
  (`<prefix>-start-date`, ...), which the dialogs already have tests and
  hooks keyed on.
  """
  attr :id_prefix, :string, required: true
  attr :event, :string, required: true
  attr :target, :any, required: true
  attr :start_date, :string, required: true
  attr :start_time, :string, default: nil
  attr :end_date, :string, required: true
  attr :end_time, :string, default: nil
  attr :all_day, :boolean, default: false

  attr :form_id, :string,
    default: nil,
    doc: "overrides `<id_prefix>-form` where a dialog already had its own form id"

  @spec date_time_range(map()) :: Phoenix.LiveView.Rendered.t()
  def date_time_range(assigns) do
    ~H"""
    <form
      id={@form_id || "#{@id_prefix}-form"}
      phx-change={@event}
      phx-target={@target}
      class="grid gap-4 sm:grid-cols-2"
    >
      <div>
        <.field_label for={"#{@id_prefix}-start-date"}>
          {dgettext("dashboard_calendar_events", "Start")}
        </.field_label>
        <div class="flex gap-2">
          <.input
            type="date"
            id={"#{@id_prefix}-start-date"}
            name="start-date"
            value={@start_date}
            class="flex-3 min-w-0"
          />
          <.input
            :if={!@all_day}
            type="time"
            id={"#{@id_prefix}-start-time"}
            name="start-time"
            value={@start_time}
            class="flex-2 min-w-0"
          />
        </div>
      </div>
      <div>
        <.field_label for={"#{@id_prefix}-end-date"}>
          {dgettext("dashboard_calendar_events", "End")}
        </.field_label>
        <div class="flex gap-2">
          <.input
            type="date"
            id={"#{@id_prefix}-end-date"}
            name="end-date"
            value={@end_date}
            class="flex-3 min-w-0"
          />
          <.input
            :if={!@all_day}
            type="time"
            id={"#{@id_prefix}-end-time"}
            name="end-time"
            value={@end_time}
            class="flex-2 min-w-0"
          />
        </div>
      </div>
    </form>
    """
  end

  @doc "“Time zone: CEST”, the zone every time in the dialog is shown in."
  attr :abbr, :string, required: true

  @spec time_zone_note(map()) :: Phoenix.LiveView.Rendered.t()
  def time_zone_note(assigns) do
    ~H"""
    <span class="text-token-sm text-neutral-500 dark:text-twilight-indigo-300">
      {dgettext("dashboard_calendar_events", "Time zone: %{zone}", zone: @abbr)}
    </span>
    """
  end

  @doc "Thin divider between the dialog's groups of fields."
  @spec divider(map()) :: Phoenix.LiveView.Rendered.t()
  def divider(assigns) do
    ~H"""
    <hr class="border-t border-neutral-300 dark:border-twilight-indigo-800" />
    """
  end
end
