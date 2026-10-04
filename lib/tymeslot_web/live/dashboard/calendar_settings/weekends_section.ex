defmodule TymeslotWeb.Dashboard.CalendarSettings.WeekendsSection do
  @moduledoc """
  Renders the "Weekends" row of the calendar settings page's "Public calendar"
  block (`PublicCalendarSection`).

  A separate module the same way `HistoricalEventsSection` is — keeps
  `PublicCalendarSection` under the project's line-count budget.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Dashboard.CalendarSettings.PublicCalendarSection

  @doc """
  Whether Saturdays and Sundays are published
  (`ProfileSchema.public_calendar_show_weekends`). Off by default. Off, the
  public calendar page shows Monday to Friday only, unless a weekend day of the
  month shown can be booked (`TymeslotWeb.Public.CalendarLive`), and weekend
  busy times are left out of the page and the free/busy feed alike
  (`Tymeslot.FreeBusy.clip_to_public_visibility/2`).
  """
  attr :enabled, :boolean, required: true
  attr :myself, :any, required: true

  @spec weekends_row(map()) :: Phoenix.LiveView.Rendered.t()
  def weekends_row(assigns) do
    ~H"""
    <div class="p-4 space-y-3">
      <PublicCalendarSection.row_heading
        icon="hero-calendar-days"
        title={dgettext("dashboard_calendar_settings", "Weekends")}
      />

      <div class="flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_calendar_settings", "Show weekends")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_calendar_settings",
              "Off by default: your public calendar shows Monday to Friday only, and your free/busy feed leaves out busy times at weekends. Saturday and Sunday still appear in a month where a weekend day can be booked. Turn this on to always show weekends, busy times included."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@enabled}
          click_event="toggle_public_calendar_show_weekends"
          target={@myself}
          aria_label={dgettext("dashboard_calendar_settings", "Set show weekends")}
        />
      </div>
    </div>
    """
  end
end
