defmodule TymeslotWeb.Dashboard.CalendarGrid.Views.StatusBanners do
  @moduledoc "Status banner function component (stale/syncing) for the calendar grid."

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers

  # ---------- Status banners ----------

  attr :stale_integrations, :list, required: true
  attr :syncing, :boolean, required: true
  attr :sync_total, :integer, required: true
  attr :sync_completed, :integer, required: true
  attr :oldest_sync_at, :any
  attr :myself, :any, required: true

  @spec status_banners(map()) :: Phoenix.LiveView.Rendered.t()
  def status_banners(assigns) do
    assigns =
      assign(
        assigns,
        :sync_progress,
        if(assigns.sync_total > 1,
          do: " (#{assigns.sync_completed}/#{assigns.sync_total})",
          else: ""
        )
      )

    ~H"""
    <%!-- Always rendered, even with no banner inside. The banners sit directly
          above the calendar's scroll container in the same flex column, and an
          element appearing or disappearing at that position shifts every
          sibling after it; morphdom then re-creates the wrapper the scroll
          container lives in, which silently resets its scrollTop to the top of
          the day. Keeping this element present keeps the sibling list stable. --%>
    <div id="calendar-status-banners">
      <div
        :if={@stale_integrations != [] and not @syncing}
        class="flex items-center gap-2 px-3 py-1.5 md:px-4 bg-amber-50 border-b border-amber-200 text-token-sm text-amber-700"
      >
        <.icon name="hero-exclamation-triangle" class="w-4 h-4 shrink-0" />
        <span>
          {if @oldest_sync_at,
            do:
              dgettext("dashboard_calendar", "Calendar data may be outdated (last synced %{age}).",
                age: Helpers.format_sync_age(@oldest_sync_at)
              ),
            else: dgettext("dashboard_calendar", "Some calendars have never been synced.")}
        </span>
        <button
          phx-click="refresh"
          phx-target={@myself}
          class="underline hover:text-amber-900 font-medium"
        >{dgettext("dashboard_calendar", "Refresh now")}</button>
      </div>
      <div
        :if={@syncing}
        class="flex items-center gap-2 px-3 py-1.5 md:px-4 bg-primary-50 border-b border-primary-200 text-token-sm text-primary-700"
      >
        <.icon name="hero-arrow-path" class="w-4 h-4 animate-spin shrink-0" />
        <span>{dgettext("dashboard_calendar", "Syncing calendars%{progress}...",
          progress: @sync_progress
        )}</span>
      </div>
    </div>
    """
  end
end
