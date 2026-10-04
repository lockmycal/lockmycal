defmodule TymeslotWeb.Dashboard.DashboardOverviewComponent do
  @moduledoc """
  LiveView component for the dashboard overview.

  Renders a bento-style dashboard: KPI tiles (`OverviewStats`), the onboarding
  checklist, side widgets (quick actions, integrations, 7-day analytics and any
  registered `Tymeslot.Dashboard.OverviewWidget`) and, as the main panel, the
  live agenda in two blocks. "Your day today" is a *focus cockpit* for today's
  next appointment (with a live countdown and a self-arming Join button) over
  a *day spine*: a vertical time-rail where free stretches are compressed into
  labelled connectors and a pulsing now-line marks the present. "Coming up
  tomorrow" lists every appointment of the next day. Bookings and synced calendar events are merged into one
  source-agnostic view upstream (`Tymeslot.Agenda`); here we only present it.
  An appointment opens in the calendar, in the same detail modal a click on the
  grid shows, so there is one detail view to keep right, not two.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Agenda.Day
  alias Tymeslot.Agenda.Entry
  alias Tymeslot.Dashboard.OverviewStats
  alias TymeslotWeb.Dashboard.AgendaTimeline
  alias TymeslotWeb.Dashboard.DashboardOverview.ComponentView

  import TymeslotWeb.Dashboard.DashboardOverviewFormatters

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    agenda = get_in(assigns, [:shared_data, :agenda]) || %Day{}
    stats = get_in(assigns, [:shared_data, :overview_stats]) || %OverviewStats{}

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:agenda, agenda)
     |> assign(:stats, stats)
     |> assign_agenda_view(agenda, DateTime.utc_now())}
  end

  # Reshapes the domain agenda into the view model the rail renders against. The
  # domain pops the hero out of its day group; here we fold it back in so the
  # spine shows where "next" actually sits, and mark it by id for the cockpit.
  defp assign_agenda_view(socket, %Day{} = agenda, now) do
    today = local_date(now, agenda.timezone)
    next_id = agenda.next && agenda.next.id

    {all_day_today, timed_today} =
      agenda |> entries_on(today) |> Enum.split_with(& &1.all_day?)

    others = Enum.reject(timed_today, &(&1.id == next_id))

    assign(socket,
      now: now,
      # The cockpit sits in the "today" block, so it only features a next
      # appointment that is today's; tomorrow's lists in the block below.
      next_today?: agenda.next != nil and Entry.covers?(agenda.next, today, agenda.timezone),
      all_day_today: all_day_today,
      spine: AgendaTimeline.spine(timed_today, now, next_id),
      today_count: length(all_day_today) + length(timed_today),
      then_entry: List.first(others),
      more_count: max(length(others) - 1, 0),
      tomorrow_entries: entries_on(agenda, Date.add(today, 1))
    )
  end

  # All entries occupying `date` (by overlap), hero folded back in, de-duplicated
  # and ordered — so a multi-day block or an in-progress overnight entry appears
  # on the day being viewed, not only the day it began.
  defp entries_on(%Day{} = agenda, date) do
    [agenda.next | agenda.today ++ agenda.tomorrow]
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&Entry.covers?(&1, date, agenda.timezone))
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.start_at, DateTime)
  end

  @impl Phoenix.LiveComponent
  def render(assigns), do: ComponentView.agenda(assigns)
end
