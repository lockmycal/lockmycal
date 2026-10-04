defmodule TymeslotWeb.Dashboard.AnalyticsLive.SummaryCards do
  @moduledoc """
  Four-card summary for the analytics dashboard: total visits, unique
  visitors, total bookings, and conversion rate over the chosen window.

  Cards stretch to a shared row height and pin their value to the bottom, so a
  label that wraps to two lines (e.g. "Conversion (est.)") never pushes its
  number out of line with its neighbours. While `loading?` is true each value
  is replaced with a skeleton, so a page load shows a brief shimmer rather than
  a misleading `0` that then jumps to the real figure. Each tile is the shared
  `TymeslotWeb.Components.Dashboard.StatCard`.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  import TymeslotWeb.Components.Dashboard.StatCard

  alias Tymeslot.Analytics

  attr :visits, :integer, required: true
  attr :unique_visitors, :integer, required: true
  attr :bookings, :integer, required: true
  attr :converting_visitors, :integer, required: true
  attr :loading?, :boolean, default: false

  @spec cards(map()) :: Phoenix.LiveView.Rendered.t()
  def cards(assigns) do
    assigns =
      assign(
        assigns,
        :conversion_rate,
        Analytics.conversion_rate(assigns.converting_visitors, assigns.unique_visitors)
      )

    ~H"""
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <.stat_card
        label={dgettext("dashboard_analytics", "Visits")}
        value={@visits}
        icon="hero-cursor-arrow-rays"
        color={:tertiary}
        loading?={@loading?}
      />
      <.stat_card
        label={dgettext("dashboard_analytics", "Unique visitors")}
        value={@unique_visitors}
        icon="hero-user-group"
        color={:primary}
        loading?={@loading?}
      />
      <.stat_card
        label={dgettext("dashboard_analytics", "Bookings")}
        value={@bookings}
        icon="hero-calendar-days"
        color={:secondary}
        loading?={@loading?}
      />
      <.stat_card
        label={dgettext("dashboard_analytics", "Conversion (est.)")}
        value={"#{@conversion_rate}%"}
        icon="hero-arrow-trending-up"
        color={:emerald}
        loading?={@loading?}
      />
    </div>
    """
  end
end
