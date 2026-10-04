defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.CalendarPicker do
  @moduledoc """
  The calendar an event is written to, picked from a native select: one
  option group per connection, one option per writable calendar in it, and
  the selected connection's colour as a dot in the closed field. Each change
  sends `event_name` with a `calendar_target` param; `expand_target/1` turns it
  into the `"integration-id"` / `"calendar-id"` pair the handlers read.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.DisplayHelpers
  alias TymeslotWeb.Dashboard.CalendarGrid.EditWorkflow
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers

  attr :integrations, :list, required: true
  attr :integration_colors, :map, required: true
  attr :selected_integration_id, :integer, required: true
  attr :selected_calendar_id, :string, default: nil
  attr :myself, :any, required: true
  attr :event_name, :string, required: true
  attr :id, :string, default: "calendar-picker"

  @spec calendar_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def calendar_picker(assigns) do
    # A connection with nothing writable is not a target. Filtering here rather
    # than at each call site means no picker can offer one, whatever list it is
    # handed.
    integrations = Calendar.writable_integrations(assigns.integrations)
    options = Enum.map(integrations, &option_group/1)

    selected_integration =
      Enum.find(integrations, &(&1.id == assigns.selected_integration_id))

    assigns =
      assigns
      |> assign(:options, options)
      |> assign(:value, selected_value(selected_integration, assigns.selected_calendar_id))
      |> assign(:selected_integration, selected_integration)
      # One choice is no choice: shown so the dialog says where the event is,
      # but not offered as a control.
      |> assign(:disabled, options |> Enum.flat_map(&elem(&1, 1)) |> length() <= 1)

    ~H"""
    <form id={"#{@id}-form"} phx-change={@event_name} phx-target={@myself}>
      <.input
        type="select"
        id={@id}
        name="calendar_target"
        value={@value}
        options={@options}
        disabled={@disabled}
        style={@selected_integration && "--leading-icon-width: 0.625rem"}
      >
        <:leading_icon :if={@selected_integration}>
          <span class={[
            "block w-2.5 h-2.5 rounded-full",
            Helpers.color_dot(%{integration_colors: @integration_colors}, @selected_integration)
          ]}></span>
        </:leading_icon>
      </.input>
    </form>
    """
  end

  @doc """
  Reads the picker's `calendar_target` value back into the
  `"integration-id"` / `"calendar-id"` params the handlers take (the calendar
  id absent for a connection written to through its provider default).
  Params without it are returned unchanged.
  """
  @spec expand_target(map()) :: map()
  def expand_target(%{"calendar_target" => target} = params) when is_binary(target) do
    case String.split(target, ":", parts: 2) do
      [integration_id, ""] ->
        Map.put(params, "integration-id", integration_id)

      [integration_id, calendar_id] ->
        Map.merge(params, %{"integration-id" => integration_id, "calendar-id" => calendar_id})

      _malformed ->
        params
    end
  end

  def expand_target(params), do: params

  # The integration id goes first because it is an integer: splitting on the
  # first colon then leaves any colon inside a calendar id where it was.
  defp target_value(integration_id, calendar_id), do: "#{integration_id}:#{calendar_id}"

  # One <optgroup> per connection, named by it; a connection whose calendars
  # have not been discovered is written to through the provider's own
  # default. A connection that *has* a list but nothing writable in it never
  # gets here — `writable_integrations/1` has already dropped it.
  defp option_group(integration) do
    options =
      case Calendar.writable_calendars(integration.calendar_list) do
        [] ->
          [
            {dgettext("dashboard_calendar_events", "Default calendar"),
             target_value(integration.id, "")}
          ]

        calendars ->
          Enum.map(calendars, fn cal ->
            {DisplayHelpers.extract_calendar_display_name(cal),
             target_value(integration.id, cal.id)}
          end)
      end

    # Upper-cased as text: a native <optgroup> label takes no CSS.
    {String.upcase(integration.name || ""), options}
  end

  defp selected_value(nil, _selected_calendar_id), do: nil

  defp selected_value(integration, selected_calendar_id) do
    calendar_id =
      if is_binary(selected_calendar_id),
        do: selected_calendar_id,
        else: EditWorkflow.default_calendar_id_for(integration)

    target_value(integration.id, calendar_id || "")
  end

  @doc """
  Derives which calendar ID within an integration an event belongs to.

  Resolves the calendar the event was synced from through
  `Calendar.calendar_for_event/2`, the same match that decides whether the
  event is visible or writable, and falls back to the integration's default
  calendar when no entry matches.
  """
  @spec derive_event_calendar_id(map(), map() | nil) :: String.t() | nil
  def derive_event_calendar_id(_event, nil), do: nil

  def derive_event_calendar_id(event, integration) do
    case Calendar.calendar_for_event(event, integration.calendar_list) do
      %{id: id} -> id
      nil -> EditWorkflow.default_calendar_id_for(integration)
    end
  end
end
