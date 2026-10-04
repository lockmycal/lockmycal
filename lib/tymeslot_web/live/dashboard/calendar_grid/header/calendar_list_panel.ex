defmodule TymeslotWeb.Dashboard.CalendarGrid.Header.CalendarListPanel do
  @moduledoc """
  The "My Calendars" panel: one row per connected integration, and beneath it
  one row per calendar that integration syncs.

  The integration row keeps the coarse toggle, because hiding a whole account in
  one click stays the common case. The rows below it are the fine control, each
  with its own toggle. Colours are not picked here: an account's colour is set
  under Calendars (Manage calendars), which is where it is looked for.

  Only calendars marked `selected` in the integration's `calendar_list` appear.
  An unselected calendar is not synced at all, so it has no events to show,
  hide, and listing it would offer a control that does nothing.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Integrations.Calendar.CalendarEntry
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers

  attr :integrations, :list, required: true
  attr :integration_colors, :map, required: true
  attr :hidden_integration_ids, :list, required: true
  attr :hidden_calendar_keys, :any, required: true
  attr :myself, :any, required: true

  @spec calendar_list_panel(map()) :: Phoenix.LiveView.Rendered.t()
  def calendar_list_panel(assigns) do
    ~H"""
    <h4 class="text-token-xs font-semibold text-neutral-500 uppercase tracking-wide mb-2">
      {dgettext("dashboard_calendar", "My Calendars")}
    </h4>

    <div :for={integration <- @integrations} class="mb-3 last:mb-0">
      <label class="flex items-center gap-2 py-1.5 cursor-pointer hover:bg-neutral-50 rounded-token-md px-1">
        <input
          type="checkbox"
          checked={integration.id not in @hidden_integration_ids}
          phx-click="toggle_integration_visibility"
          phx-value-integration-id={integration.id}
          phx-target={@myself}
          class="rounded"
        />
        <div
          class={"w-3 h-3 rounded-full shrink-0 #{Helpers.color_class_for_integration(@integration_colors, integration.id)}"}
          aria-hidden="true"
        >
        </div>
        <span class="text-token-sm font-semibold text-neutral-700 dark:text-neutral-200 truncate">
          {integration.name}
        </span>
      </label>

      <div
        :for={calendar <- synced_calendars(integration)}
        class="ml-4 border-l-2 border-neutral-300 pl-3"
      >
        <label class="flex items-center gap-2 py-1 cursor-pointer hover:bg-neutral-50 rounded-token-md px-1">
          <input
            type="checkbox"
            checked={not hidden?(@hidden_calendar_keys, integration.id, calendar.id)}
            phx-click="toggle_calendar_visibility"
            phx-value-integration-id={integration.id}
            phx-value-calendar-id={calendar.id}
            phx-target={@myself}
            class="rounded"
          />
          <span class="text-token-sm text-neutral-600 dark:text-neutral-300 truncate">{calendar.name}</span>
        </label>
      </div>
    </div>

    <p :if={@integrations == []} class="text-token-sm text-neutral-400">
      {dgettext("dashboard_calendar", "No calendars connected")}
    </p>
    """
  end

  # `calendar_list` is persisted as embedded entries, but a hand-written row or
  # an older record may still be a plain map, so normalise before reading.
  defp synced_calendars(integration) do
    integration.calendar_list
    |> Enum.map(&CalendarEntry.normalize/1)
    |> Enum.filter(&(&1.selected and is_binary(&1.id)))
  end

  defp hidden?(hidden_keys, integration_id, calendar_id),
    do: MapSet.member?(hidden_keys, {integration_id, calendar_id})
end
