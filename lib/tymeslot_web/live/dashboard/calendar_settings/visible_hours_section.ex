defmodule TymeslotWeb.Dashboard.CalendarSettings.VisibleHoursSection do
  @moduledoc """
  Renders the "Visible hours" row of the calendar settings page's "Public
  calendar" block (`PublicCalendarSection`).

  A separate module purely to keep `PublicCalendarSection` under the
  project's line-count budget — this row has no other reason to be separate.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Shared.TimeOptions
  alias TymeslotWeb.Dashboard.CalendarSettings.PublicCalendarSection

  @doc """
  An optional daily time-of-day window that clips which busy blocks appear
  on the public calendar page and the free/busy ICS feed
  (`Tymeslot.FreeBusy.clip_to_visible_window/4`). Off by default
  (`nil`/`nil`, meaning no restriction); the two time selects only show
  once enabled, mirroring `CancelledMeetingsRetentionFormComponent`'s
  toggle-plus-conditional-field layout.
  """
  attr :visible_from, :any, default: nil
  attr :visible_to, :any, default: nil
  attr :myself, :any, required: true

  @spec visible_hours_row(map()) :: Phoenix.LiveView.Rendered.t()
  def visible_hours_row(assigns) do
    assigns = assign(assigns, :enabled, assigns.visible_from != nil and assigns.visible_to != nil)

    ~H"""
    <div class="p-4 space-y-3">
      <PublicCalendarSection.row_heading
        icon="hero-clock"
        title={dgettext("dashboard_calendar_settings", "Visible hours")}
      />

      <div class="space-y-4">
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <div class="min-w-0 flex-1 space-y-1">
            <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
              {dgettext(
                "dashboard_calendar_settings",
                "Only show busy times within a daily window"
              )}
            </p>
            <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
              {dgettext(
                "dashboard_calendar_settings",
                "Your public calendar and free/busy feed show busy blocks around the clock by default. Turn this on to hide anything outside a daily time range, e.g. 07:00–18:00."
              )}
            </p>
          </div>
          <.enabled_toggle
            active={@enabled}
            click_event="toggle_public_calendar_visible_hours"
            target={@myself}
            aria_label={dgettext("dashboard_calendar_settings", "Set visible hours")}
          />
        </div>

        <form
          :if={@enabled}
          id="public-calendar-visible-hours-form"
          phx-change="update_public_calendar_visible_hours"
          phx-target={@myself}
          phx-debounce="500"
          class="flex items-end gap-2"
        >
          <.input
            type="select"
            name="from"
            label={dgettext("dashboard_calendar_settings", "From")}
            options={TimeOptions.time_options()}
            value={format_visible_time(@visible_from)}
          />
          <span class="text-neutral-400 pb-2">–</span>
          <.input
            type="select"
            name="to"
            label={dgettext("dashboard_calendar_settings", "To")}
            options={TimeOptions.time_options()}
            value={format_visible_time(@visible_to)}
          />
        </form>
      </div>
    </div>
    """
  end

  defp format_visible_time(nil), do: ""

  # `Calendar` isn't aliased in this module (unlike `Components`, where it
  # means `Tymeslot.Integrations.Calendar`), so the built-in works unqualified.
  defp format_visible_time(%Time{} = time), do: Calendar.strftime(time, "%H:%M")
end
