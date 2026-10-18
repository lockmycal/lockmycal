defmodule TymeslotWeb.Dashboard.CalendarUpNextStrip do
  @moduledoc """
  Slim "Up next" strip rendered above the calendar grid.

  A compact cousin of the overview's focus cockpit: the next appointment's
  title, time and counterpart, a live countdown, and a Join button that the
  `AgendaCountdown` hook reveals as the start approaches.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Dashboard.Appointments.JoinLink
  alias TymeslotWeb.Dashboard.DashboardFormat

  attr :entry, :map, required: true
  attr :timezone, :string, required: true
  attr :time_format, :string, required: true

  @spec up_next_strip(map()) :: Phoenix.LiveView.Rendered.t()
  def up_next_strip(assigns) do
    ~H"""
    <div
      class="relative isolate overflow-hidden bg-linear-to-br from-primary-600 to-secondary-600 text-white mx-3 md:mx-4 flex items-center gap-3 rounded-token-xl px-4 py-2.5 shrink-0"
      data-testid="up-next-strip"
    >
      <div class="absolute inset-0 -z-10 pointer-events-none bg-[radial-gradient(circle_at_20%_20%,rgba(255,255,255,0.15),transparent_55%)]">
      </div>
      <div class="flex items-center gap-1.5 text-token-xs font-black uppercase tracking-widest text-white/80 shrink-0">
        <.icon name="hero-bolt-mini" class="w-4 h-4" />
        <span class="hidden sm:inline">{dgettext("dashboard_home", "Up next")}</span>
      </div>
      <div class="min-w-0 flex-1 truncate text-token-sm font-semibold">
        {DashboardFormat.title(@entry.title)}
        <span class="text-white/80 font-medium">
          · {DashboardFormat.day_label(@entry, @timezone)} · {DashboardFormat.start_label(
            @entry,
            @timezone,
            @time_format
          )}<span :if={@entry.who}> · {@entry.who}</span>
        </span>
      </div>
      <JoinLink.agenda_countdown
        entry={@entry}
        id_prefix="calendar-up-next"
        class="text-token-lg shrink-0"
      />
    </div>
    """
  end
end
