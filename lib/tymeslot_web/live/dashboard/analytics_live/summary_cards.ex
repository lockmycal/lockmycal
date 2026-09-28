defmodule TymeslotWeb.Dashboard.AnalyticsLive.SummaryCards do
  @moduledoc """
  Four-card summary for the analytics dashboard: total visits, unique
  visitors, total bookings, and conversion rate over the chosen window.

  Cards stretch to a shared row height and pin their value to the bottom, so a
  label that wraps to two lines (e.g. "Conversion (est.)") never pushes its
  number out of line with its neighbours. While `loading?` is true each value
  is replaced with a skeleton, so a page load shows a brief shimmer rather than
  a misleading `0` that then jumps to the real figure.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

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

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :color, :atom, required: true, values: [:primary, :secondary, :tertiary, :emerald]
  attr :loading?, :boolean, default: false

  defp stat_card(assigns) do
    ~H"""
    <div class="card-glass flex h-full flex-col">
      <div class="flex items-center gap-3">
        <div class={[
          "flex h-9 w-9 shrink-0 items-center justify-center rounded-token-lg",
          icon_box_class(@color)
        ]}>
          <.icon name={@icon} class="h-5 w-5" />
        </div>
        <div class="text-token-sm font-black uppercase tracking-widest text-neutral-400 dark:text-twilight-indigo-300">
          {@label}
        </div>
      </div>
      <div class="mt-auto pt-3">
        <div
          :if={@loading?}
          class="h-9 w-20 animate-pulse rounded-token-md bg-neutral-100 dark:bg-twilight-indigo-800"
          aria-hidden="true"
        >
        </div>
        <div
          :if={!@loading?}
          class={["text-token-3xl font-black tracking-tight tabular-nums", value_class(@color)]}
        >
          {@value}
        </div>
      </div>
    </div>
    """
  end

  # Full literal class strings (not interpolated) so Tailwind's content
  # scanner (`@source "../../lib/tymeslot_web"` in assets/css/app.css) picks
  # them up at build time.
  defp icon_box_class(:tertiary), do: "bg-tertiary-500 text-white"
  defp icon_box_class(:primary), do: "bg-primary-500 text-white"
  defp icon_box_class(:secondary), do: "bg-secondary-500 text-white"
  defp icon_box_class(:emerald), do: "bg-emerald-500 text-white"

  defp value_class(:tertiary), do: "text-tertiary-700 dark:text-tertiary-300"
  defp value_class(:primary), do: "text-primary-700 dark:text-primary-300"
  defp value_class(:secondary), do: "text-secondary-700 dark:text-secondary-300"
  defp value_class(:emerald), do: "text-emerald-700 dark:text-emerald-300"
end
