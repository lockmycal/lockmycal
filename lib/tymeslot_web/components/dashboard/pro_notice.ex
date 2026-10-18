defmodule TymeslotWeb.Components.Dashboard.ProNotice do
  @moduledoc """
  Amber info strip explaining that a feature is only available on a paid plan.
  Shared by every locked in-page action/section (e.g. the meeting-type "Change
  link" note in `ServiceSettings.ComponentView`, the Custom URL and Contact
  Collection sections) so the Pro hint looks the same everywhere; the "Pro"
  pill next to the heading stays `ProBadge`'s job.

  `icon` replaces the default lock for a note that is about something else the
  plan unlocks (e.g. payments).
  """

  use TymeslotWeb, :html

  attr :icon, :string, default: "hero-lock-closed"
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  @spec pro_notice(map()) :: Phoenix.LiveView.Rendered.t()
  def pro_notice(assigns) do
    ~H"""
    <div
      class={[
        "flex items-center gap-2 text-token-sm font-medium px-3 py-2 rounded-token-xl border border-amber-200 bg-amber-50 text-amber-800 dark:bg-amber-950/40 dark:border-amber-800 dark:text-amber-300",
        @class
      ]}
      {@rest}
    >
      <.icon name={@icon} class="w-4 h-4 shrink-0" />
      <div class="min-w-0">{render_slot(@inner_block)}</div>
    </div>
    """
  end
end
