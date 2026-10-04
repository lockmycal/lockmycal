defmodule TymeslotWeb.Components.Dashboard.StatCard do
  @moduledoc """
  A single KPI tile: a coloured icon box, an uppercase label and a large value
  pinned to the bottom, so tiles in one row line up even when a label wraps.

  Shared by the Analytics summary row (`AnalyticsLive.SummaryCards`) and the
  Overview's KPI row — extracted here once it had a second caller, per the
  shared-widget convention. With `navigate` the whole tile is a link to the
  page behind the figure. While `loading?` is true the value is replaced with a
  skeleton, so a page load never shows a misleading `0` that then jumps.
  """
  use TymeslotWeb, :html

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true

  attr :color, :atom,
    required: true,
    values: [:primary, :secondary, :tertiary, :emerald, :amber]

  attr :hint, :string, default: nil, doc: "optional muted line under the value"
  attr :navigate, :string, default: nil, doc: "makes the whole tile a link"
  attr :loading?, :boolean, default: false
  attr :rest, :global

  @spec stat_card(map()) :: Phoenix.LiveView.Rendered.t()
  def stat_card(%{navigate: nil} = assigns) do
    ~H"""
    <div class="card-glass flex h-full flex-col" {@rest}>
      <.stat_card_body {assigns} />
    </div>
    """
  end

  def stat_card(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="card-glass group flex h-full flex-col focus:outline-hidden focus:ring-2 focus:ring-primary-400"
      {@rest}
    >
      <.stat_card_body {assigns} />
    </.link>
    """
  end

  defp stat_card_body(assigns) do
    ~H"""
    <%!-- flex-wrap + basis-20: the label wraps onto two lines beside the icon,
         and only drops below it when even that leaves under 5rem (a narrow
         two-column phone grid) — rather than overflowing the tile. --%>
    <div class="flex flex-wrap items-center gap-3">
      <div class={[
        "flex h-9 w-9 shrink-0 items-center justify-center rounded-token-lg",
        icon_box_class(@color)
      ]}>
        <.icon name={@icon} class="h-5 w-5" />
      </div>
      <div class="min-w-0 grow basis-20 text-token-sm font-black uppercase tracking-widest text-neutral-400 dark:text-twilight-indigo-300">
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
      <div
        :if={@hint}
        class="mt-1 text-token-xs font-semibold text-neutral-500 dark:text-twilight-indigo-300"
      >
        {@hint}<span
          :if={@navigate}
          class="inline-block pl-1 transition-transform group-hover:translate-x-0.5"
          aria-hidden="true"
        >→</span>
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
  defp icon_box_class(:amber), do: "bg-amber-500 text-white"

  defp value_class(:tertiary), do: "text-tertiary-700 dark:text-tertiary-300"
  defp value_class(:primary), do: "text-primary-700 dark:text-primary-300"
  defp value_class(:secondary), do: "text-secondary-700 dark:text-secondary-300"
  defp value_class(:emerald), do: "text-emerald-700 dark:text-emerald-300"
  defp value_class(:amber), do: "text-amber-700 dark:text-amber-300"
end
