defmodule TymeslotWeb.Dashboard.DashboardOverview.Widgets do
  @moduledoc """
  The Overview's KPI row and built-in side-column widgets — quick actions,
  integrations and the 7-day analytics summary — rendered by
  `DashboardOverview.ComponentView` around the live agenda. Split out so the
  view keeps to the agenda's own vocabulary (cockpit, spine, tomorrow row).

  Figures come from `Tymeslot.Dashboard.OverviewStats`; the widgets are
  stateless function components with no events of their own (the only
  interactive bits are links, the copy-to-clipboard hook and the dashboard-wide
  share modal they target).
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  import TymeslotWeb.Components.Dashboard.StatCard

  alias Tymeslot.Dashboard.OverviewStats
  alias Tymeslot.Utils.UrlBuilder
  alias TymeslotWeb.Components.Dashboard.Sparkline
  alias TymeslotWeb.Dashboard.AnalyticsLive.VisitsChart
  alias TymeslotWeb.Helpers.LocaleFormat

  # --- KPI row ---------------------------------------------------------------

  attr :today_count, :integer, required: true
  attr :stats, OverviewStats, required: true

  @spec kpi_row(map()) :: Phoenix.LiveView.Rendered.t()
  def kpi_row(assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-3 sm:gap-4 lg:grid-cols-4">
      <.stat_card
        id="overview-kpi-today"
        label={dgettext("dashboard_home", "Today")}
        value={@today_count}
        icon="hero-calendar"
        color={:primary}
        hint={dgettext("dashboard_home", "Open calendar")}
        navigate={~p"/dashboard"}
      />
      <.stat_card
        id="overview-kpi-week"
        label={dgettext("dashboard_home", "This week")}
        value={@stats.week_bookings}
        icon="hero-calendar-days"
        color={:secondary}
        hint={dgettext("dashboard_home", "Bookings")}
        navigate={~p"/dashboard/meetings"}
      />
      <.stat_card
        id="overview-kpi-approval"
        label={dgettext("dashboard_home", "Awaiting approval")}
        value={@stats.awaiting_approval}
        icon="hero-inbox-arrow-down"
        color={if @stats.awaiting_approval > 0, do: :amber, else: :tertiary}
        hint={dgettext("dashboard_home", "Review")}
        navigate={~p"/dashboard/meetings"}
      />
      <.stat_card
        id="overview-kpi-polls"
        label={dgettext("dashboard_home", "Open polls")}
        value={@stats.open_polls}
        icon="hero-hand-raised"
        color={:emerald}
        hint={dgettext("dashboard_home", "Polls")}
        navigate={~p"/dashboard/polls"}
      />
    </div>
    """
  end

  # --- Quick actions ---------------------------------------------------------

  attr :can_link?, :boolean, required: true
  attr :profile, :map, required: true

  @spec quick_actions(map()) :: Phoenix.LiveView.Rendered.t()
  def quick_actions(assigns) do
    ~H"""
    <section class="space-y-4">
      <.subsection_header icon="hero-bolt" title={dgettext("dashboard_home", "Quick actions")} />
      <div class="card-glass p-2 space-y-1">
        <.link
          id="overview-create-meeting"
          navigate={~p"/dashboard?create=1"}
          class={quick_action_class()}
        >
          <.quick_action_icon icon="hero-plus" />
          {dgettext("dashboard_home", "Create a meeting")}
        </.link>
        <%= if @can_link? do %>
          <button
            id="overview-copy-booking-link"
            type="button"
            phx-hook="CopyOnClick"
            data-copy-text={UrlBuilder.booking_url(@profile.username)}
            data-copy-feedback={dgettext("dashboard_common", "Scheduling link copied to clipboard!")}
            class={quick_action_class()}
          >
            <.quick_action_icon icon="hero-clipboard" />
            {dgettext("dashboard_home", "Copy booking link")}
          </button>
          <button
            id="overview-email-booking-link"
            type="button"
            phx-click="open"
            phx-target="#share-links-modal"
            class={quick_action_class()}
          >
            <.quick_action_icon icon="hero-envelope" />
            {dgettext("dashboard_common", "Send links by email")}
          </button>
        <% end %>
        <.link navigate={~p"/dashboard/polls"} class={quick_action_class()}>
          <.quick_action_icon icon="hero-hand-raised" />
          {dgettext("dashboard_home", "Create a poll")}
        </.link>
        <.link navigate={~p"/dashboard/meeting-settings"} class={quick_action_class()}>
          <.quick_action_icon icon="hero-squares-2x2" />
          {dgettext("dashboard_home", "Meeting types")}
        </.link>
        <.link navigate={~p"/dashboard/availability"} class={quick_action_class()}>
          <.quick_action_icon icon="hero-clock" />
          {dgettext("dashboard_home", "Availability")}
        </.link>
      </div>
    </section>
    """
  end

  defp quick_action_class do
    "flex w-full items-center gap-3 rounded-token-xl px-3 py-2 text-left text-token-sm font-bold text-neutral-700 dark:text-neutral-200 hover:bg-neutral-100 dark:hover:bg-twilight-indigo-800 hover:text-primary-700 dark:hover:text-primary-300 focus:outline-hidden focus:ring-2 focus:ring-primary-400 transition-colors cursor-pointer"
  end

  attr :icon, :string, required: true

  defp quick_action_icon(assigns) do
    ~H"""
    <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-token-lg bg-primary-50 dark:bg-primary-950/40 text-primary-600 dark:text-primary-300">
      <.icon name={@icon} class="h-4 w-4" />
    </span>
    """
  end

  # --- Integrations ----------------------------------------------------------

  attr :integration_status, :map, required: true
  attr :stats, OverviewStats, required: true

  @spec integrations_widget(map()) :: Phoenix.LiveView.Rendered.t()
  def integrations_widget(assigns) do
    ~H"""
    <section class="space-y-4">
      <.subsection_header icon="hero-puzzle-piece" title={dgettext("dashboard_home", "Integrations")} />
      <div class="card-glass p-2 space-y-1">
        <.integration_row
          id="overview-integration-calendars"
          icon="hero-calendar-days"
          label={dgettext("dashboard_home", "Calendars")}
          count={@integration_status.calendar_count}
          attention={@stats.calendar_attention}
          navigate={~p"/dashboard/calendar-integration"}
        />
        <.integration_row
          id="overview-integration-video"
          icon="hero-video-camera"
          label={dgettext("dashboard_home", "Video")}
          count={@integration_status.video_count}
          attention={@stats.video_attention}
          navigate={~p"/dashboard/video-integration"}
        />
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, required: true
  attr :attention, :integer, required: true
  attr :navigate, :string, required: true

  defp integration_row(assigns) do
    ~H"""
    <.link id={@id} navigate={@navigate} class={quick_action_class()}>
      <.quick_action_icon icon={@icon} />
      <span class="flex-1 min-w-0 truncate">{@label}</span>
      <span
        :if={@attention > 0}
        class="shrink-0 rounded-token-full bg-amber-100 dark:bg-amber-950/40 px-2 py-0.5 text-token-xs font-black text-amber-800 dark:text-amber-200"
      >
        {dngettext(
          "dashboard_home",
          "%{count} needs attention",
          "%{count} need attention",
          @attention
        )}
      </span>
      <span
        :if={@attention == 0 and @count > 0}
        class="shrink-0 rounded-token-full bg-emerald-100 dark:bg-emerald-950/40 px-2 py-0.5 text-token-xs font-black text-emerald-800 dark:text-emerald-200"
      >
        {dngettext("dashboard_home", "%{count} active", "%{count} active", @count)}
      </span>
      <span
        :if={@attention == 0 and @count == 0}
        class="shrink-0 rounded-token-full bg-neutral-100 dark:bg-twilight-indigo-800 px-2 py-0.5 text-token-xs font-black text-neutral-600 dark:text-neutral-300"
      >
        {dgettext("dashboard_home", "Not connected")}
      </span>
    </.link>
    """
  end

  # --- Analytics -------------------------------------------------------------

  attr :analytics, :map, required: true
  attr :timezone, :string, required: true

  @spec analytics_widget(map()) :: Phoenix.LiveView.Rendered.t()
  def analytics_widget(assigns) do
    locale = Gettext.get_locale(TymeslotWeb.Gettext)

    points =
      assigns.analytics.visits_by_day
      |> VisitsChart.build_series(assigns.analytics.from, assigns.analytics.to, assigns.timezone)
      |> Enum.map(fn %{day: day, visits: visits} ->
        %{
          label:
            "#{LocaleFormat.format_weekday_name(Date.day_of_week(day), locale, :short)} #{day.day} #{LocaleFormat.format_month_name(day.month, locale, :short)}",
          value: visits
        }
      end)

    assigns = assign(assigns, :points, points)

    ~H"""
    <section id="overview-analytics" class="space-y-4">
      <.subsection_header
        icon="hero-chart-bar"
        title={dgettext("dashboard_home", "Last 7 days")}
      />
      <.link
        navigate={~p"/dashboard/analytics"}
        class="card-glass group block p-4 focus:outline-hidden focus:ring-2 focus:ring-primary-400"
      >
        <div class="grid grid-cols-3 gap-2">
          <.analytics_figure label={dgettext("dashboard_home", "Visits")} value={@analytics.visits} />
          <.analytics_figure
            label={dgettext("dashboard_home", "Bookings")}
            value={@analytics.bookings}
          />
          <.analytics_figure
            label={dgettext("dashboard_home", "Conversion")}
            value={"#{@analytics.conversion_rate}%"}
          />
        </div>
        <Sparkline.sparkline
          points={@points}
          label={dgettext("dashboard_home", "Daily visits over the last 7 days")}
          class="mt-4 h-12 w-full"
        />
        <div class="mt-3 flex items-center gap-1 text-token-xs font-bold text-primary-600 dark:text-primary-300">
          {dgettext("dashboard_home", "Open analytics")}
          <span class="transition-transform group-hover:translate-x-0.5" aria-hidden="true">→</span>
        </div>
      </.link>
    </section>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true

  defp analytics_figure(assigns) do
    ~H"""
    <div class="min-w-0">
      <div class="text-token-xs font-black uppercase tracking-widest text-neutral-400 dark:text-twilight-indigo-300 truncate">
        {@label}
      </div>
      <div class="mt-1 text-token-xl font-black tabular-nums text-neutral-900 dark:text-neutral-50">
        {@value}
      </div>
    </div>
    """
  end
end
