defmodule TymeslotWeb.Components.Dashboard.Sparkline do
  @moduledoc """
  A small inline-SVG bar chart for a short series (e.g. 7 days of visits) in a
  dashboard widget. Pure SVG like `AnalyticsLive.VisitsChart`, so it needs no
  JS hook and renders on first paint; axis labelling is left to the caller —
  a sparkline shows the shape, the widget around it states the numbers.

  The bars stretch to the element's width (`preserveAspectRatio="none"`); each
  carries a `<title>` so hovering a bar shows its label and value.
  """
  use TymeslotWeb, :html

  @width 100
  @height 32
  @gap_ratio 0.25

  attr :points, :list, required: true, doc: "list of %{label: String.t(), value: non_neg_integer}"
  attr :label, :string, required: true, doc: "accessible name of the chart"
  attr :class, :string, default: "h-12 w-full"

  @spec sparkline(map()) :: Phoenix.LiveView.Rendered.t()
  def sparkline(assigns) do
    count = max(length(assigns.points), 1)
    max_value = assigns.points |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end) |> max(1)
    step = @width / count

    bars =
      assigns.points
      |> Enum.with_index()
      |> Enum.map(fn {point, idx} ->
        # A zero day keeps a hairline so the series still reads as a week.
        height = max(@height * point.value / max_value, 1)

        %{
          x: idx * step + step * @gap_ratio / 2,
          y: @height - height,
          width: step * (1 - @gap_ratio),
          height: height,
          title: "#{point.label}: #{point.value}"
        }
      end)

    assigns = assign(assigns, bars: bars, width: @width, height: @height)

    ~H"""
    <svg
      viewBox={"0 0 #{@width} #{@height}"}
      preserveAspectRatio="none"
      class={@class}
      role="img"
      aria-label={@label}
    >
      <rect
        :for={bar <- @bars}
        x={bar.x}
        y={bar.y}
        width={bar.width}
        height={bar.height}
        rx="0.75"
        class="fill-primary-500"
      >
        <title>{bar.title}</title>
      </rect>
    </svg>
    """
  end
end
