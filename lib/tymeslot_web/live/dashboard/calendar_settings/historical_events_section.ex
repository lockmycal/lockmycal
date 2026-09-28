defmodule TymeslotWeb.Dashboard.CalendarSettings.HistoricalEventsSection do
  @moduledoc """
  Renders the "Historical events" row of the calendar settings page's "Public
  calendar" block (`PublicCalendarSection`).

  A separate module the same way `VisibleHoursSection` is — keeps
  `PublicCalendarSection` under the project's line-count budget, not because
  this toggle needs its own module otherwise.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Dashboard.CalendarSettings.PublicCalendarSection

  @doc """
  Whether the public calendar page also renders busy/pending-approval chips
  for days before today (`ProfileSchema.public_calendar_show_historical_events`,
  applied in `TymeslotWeb.Public.CalendarLive`'s `filter_historical/4`). Off
  by default — a visitor sees only today and later. Doesn't affect the
  free/busy ICS feed, which never includes past events regardless of this
  setting (its window always starts at "now").
  """
  attr :enabled, :boolean, required: true
  attr :myself, :any, required: true

  @spec historical_events_row(map()) :: Phoenix.LiveView.Rendered.t()
  def historical_events_row(assigns) do
    ~H"""
    <div class="p-4 space-y-3">
      <PublicCalendarSection.row_heading
        icon="hero-archive-box"
        title={dgettext("dashboard_calendar_settings", "Historical events")}
      />

      <div class="flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_calendar_settings", "Show historical events")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_calendar_settings",
              "Off by default: your public calendar only shows today and later. Turn this on to also show past busy times when a visitor browses to an earlier month."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@enabled}
          click_event="toggle_public_calendar_show_historical_events"
          target={@myself}
          aria_label={dgettext("dashboard_calendar_settings", "Set show historical events")}
        />
      </div>
    </div>
    """
  end
end
