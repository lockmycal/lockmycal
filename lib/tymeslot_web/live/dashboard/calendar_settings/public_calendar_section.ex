defmodule TymeslotWeb.Dashboard.CalendarSettings.PublicCalendarSection do
  @moduledoc """
  The calendar settings page's "Public calendar" block: every setting of the
  host's public busy/free calendar (`/:username/calendar`) as rows of one
  card — whether it is shown at all, colours, the visible-hours window and
  historical events.

  The visible-hours and historical-events rows live in their own modules
  (`VisibleHoursSection`, `HistoricalEventsSection`) to keep each file within
  the project's line-count budget; `row_heading/1` gives all rows the same
  heading.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Profiles
  alias TymeslotWeb.Dashboard.CalendarSettings.HistoricalEventsSection
  alias TymeslotWeb.Dashboard.CalendarSettings.VisibleHoursSection

  @doc "Renders the whole block for the host's `profile` (may be `nil` while loading)."
  attr :profile, :any, required: true
  attr :myself, :any, required: true

  @spec public_calendar_section(map()) :: Phoenix.LiveView.Rendered.t()
  def public_calendar_section(assigns) do
    ~H"""
    <section id="public-calendar-settings" class="space-y-4">
      <.subsection_header
        icon="hero-globe-alt"
        title={dgettext("dashboard_calendar_settings", "Public calendar")}
      />

      <div class="card-glass p-0! overflow-hidden divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <.enabled_row enabled={Profiles.public_calendar_enabled?(@profile)} myself={@myself} />
        <.colors_row enabled={!!(@profile && @profile.public_calendar_colors)} myself={@myself} />
        <VisibleHoursSection.visible_hours_row
          visible_from={@profile && @profile.public_calendar_visible_from}
          visible_to={@profile && @profile.public_calendar_visible_to}
          myself={@myself}
        />
        <HistoricalEventsSection.historical_events_row
          enabled={!!(@profile && @profile.public_calendar_show_historical_events)}
          myself={@myself}
        />
      </div>
    </section>
    """
  end

  @doc "The small icon + title heading every row of the block starts with."
  attr :icon, :string, required: true
  attr :title, :string, required: true

  @spec row_heading(map()) :: Phoenix.LiveView.Rendered.t()
  def row_heading(assigns) do
    ~H"""
    <h4 class="flex items-center gap-2 text-token-xs font-black uppercase tracking-wider text-neutral-500 dark:text-twilight-indigo-300">
      <.icon name={@icon} class="w-4 h-4" />
      {@title}
    </h4>
    """
  end

  # Whether the public calendar is shown at all
  # (`profile.public_calendar_enabled`, see `Profiles.public_calendar_enabled?/1`).
  attr :enabled, :boolean, required: true
  attr :myself, :any, required: true

  defp enabled_row(assigns) do
    ~H"""
    <div class="p-4 space-y-3">
      <.row_heading icon="hero-eye" title={dgettext("dashboard_calendar_settings", "Visibility")} />
      <div class="flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_calendar_settings", "Show my public calendar")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_calendar_settings",
              "When enabled, anyone with your link can see a month view of when you are busy or free — never event titles or attendees. Your booking page works either way."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@enabled}
          click_event="toggle_public_calendar_enabled"
          target={@myself}
          aria_label={dgettext("dashboard_calendar_settings", "Set public calendar visibility")}
        />
      </div>
    </div>
    """
  end

  # Whether busy blocks use each source calendar's own colour instead of one
  # neutral colour (`profile.public_calendar_colors`).
  attr :enabled, :boolean, required: true
  attr :myself, :any, required: true

  defp colors_row(assigns) do
    ~H"""
    <div class="p-4 space-y-3">
      <.row_heading
        icon="hero-swatch"
        title={dgettext("dashboard_calendar_settings", "Colour settings")}
      />
      <div class="flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_calendar_settings", "Use colours in the public calendar")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_calendar_settings",
              "Your public booking calendar shows busy times as plain grey blocks by default. Turn this on to use each calendar's colour instead, matching your internal calendar view."
            )}
          </p>
        </div>
        <div
          role="group"
          aria-label={dgettext("dashboard_calendar_settings", "Set public calendar colors")}
          class="inline-flex p-1 bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1 shrink-0"
        >
          <button
            :for={{active?, label} <- [{true, :enabled}, {false, :disabled}]}
            type="button"
            phx-click="toggle_public_calendar_colors"
            phx-target={@myself}
            disabled={@enabled == active?}
            aria-pressed={@enabled == active?}
            class={[
              "px-3 py-1.5 rounded-token-lg text-token-xs font-black uppercase tracking-wider transition-all",
              if(@enabled == active?,
                do: "bg-primary-600 text-white cursor-default",
                else:
                  "text-neutral-500 dark:text-neutral-50 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 hover:text-neutral-900 dark:hover:text-neutral-50 cursor-pointer"
              )
            ]}
          >
            {toggle_label(label)}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp toggle_label(:enabled), do: dgettext("dashboard_calendar_settings", "Enabled")
  defp toggle_label(:disabled), do: dgettext("dashboard_calendar_settings", "Disabled")
end
