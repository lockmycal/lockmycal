defmodule TymeslotWeb.Dashboard.CalendarGrid.Views.EmptyState do
  @moduledoc "Connect-a-calendar banner shown above the grid while no calendar is connected."

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config

  @doc """
  Slim banner inviting the user to connect a calendar.

  The grid stays live underneath — bookings render natively without any
  integration — so this nudges rather than blocks.
  """
  @spec connect_calendar_banner(map()) :: Phoenix.LiveView.Rendered.t()
  def connect_calendar_banner(assigns) do
    ~H"""
    <div
      class="flex flex-wrap items-center gap-3 px-4 py-3 mx-3 mt-2 mb-1 md:mx-4 rounded-token-xl border border-primary-200 bg-primary-50"
      data-testid="connect-calendar-banner"
    >
      <div class="w-9 h-9 shrink-0 rounded-token-lg bg-white flex items-center justify-center border border-primary-100">
        <.icon name="hero-calendar-days" class="w-5 h-5 text-primary-600" />
      </div>
      <div class="flex-1 min-w-[12rem]">
        <p class="text-token-sm font-semibold text-neutral-800 dark:text-neutral-100">
          {dgettext("dashboard_calendar", "Bring your calendar into %{app_name}",
            app_name: Config.app_name()
          )}
        </p>
        <p class="text-token-xs text-neutral-500">
          {dgettext(
            "dashboard_calendar",
            "Your bookings already show here. Connect a calendar to see the rest of your events and prevent double-bookings."
          )}
        </p>
      </div>
      <.link
        patch={~p"/dashboard/calendar-integration"}
        class="inline-flex items-center gap-1.5 px-3.5 py-2 bg-primary-600 hover:bg-primary-700 text-white text-token-sm font-semibold rounded-token-lg transition-colors shrink-0"
      >
        <.icon name="hero-plus" class="w-4 h-4" />
        {dgettext("dashboard_calendar", "Connect a calendar")}
      </.link>
    </div>
    """
  end
end
