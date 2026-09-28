defmodule TymeslotWeb.Dashboard.ThemeSettings.ThemeCustomization.CurrentIndicator do
  @moduledoc """
  Pill component that shows the active theme selection — used by both the
  Color Palette and Solid Color sections.

  Pass one or more `swatches` (CSS `background` values: hex, rgba, gradient
  strings — anything inline-style accepts), a short `label`, an optional
  monospace `code` (e.g. the hex), and `highlighted: true` when the active
  selection is a custom value rather than a curated preset. The highlight
  swaps the muted neutral palette for the same primary-colour treatment that
  signals "selected" elsewhere in the customisation UI.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :swatches, :list,
    required: true,
    doc: "List of CSS `background` values rendered as small dots."

  attr :label, :string, required: true
  attr :code, :string, default: nil, doc: "Optional monospace value shown after the label."

  attr :highlighted, :boolean,
    default: false,
    doc: "Turquoise treatment when the active selection is a custom value."

  @spec current_indicator(map()) :: Phoenix.LiveView.Rendered.t()
  def current_indicator(assigns) do
    ~H"""
    <div class={[
      "flex flex-wrap items-center gap-x-3 gap-y-1.5 px-3 py-2 rounded-token-2xl border shadow-inner sm:px-4",
      if(@highlighted,
        do: "bg-primary-50 dark:bg-primary-950/40 border-primary-300 dark:border-primary-700",
        else:
          "bg-neutral-50 dark:bg-twilight-indigo-900/60 border-neutral-300 dark:border-twilight-indigo-700"
      )
    ]}>
      <span class={[
        "text-token-2xs font-black uppercase tracking-widest",
        if(@highlighted,
          do: "text-primary-500 dark:text-primary-400",
          else: "text-neutral-400 dark:text-twilight-indigo-300"
        )
      ]}>
        {dgettext("dashboard_appearance", "Current")}
      </span>
      <div class={[
        "flex items-center gap-1.5 bg-white dark:bg-twilight-indigo-950 p-1 rounded-token-lg border",
        if(@highlighted,
          do: "border-primary-200 dark:border-primary-700",
          else: "border-neutral-300 dark:border-twilight-indigo-700"
        )
      ]}>
        <%= for swatch <- @swatches do %>
          <div class="w-3 h-3 rounded-full" style={"background: #{swatch}"}></div>
        <% end %>
      </div>
      <span class={[
        "text-token-sm font-black",
        if(@highlighted,
          do: "text-primary-700 dark:text-primary-300",
          else: "text-neutral-700 dark:text-neutral-200"
        )
      ]}>
        {@label}
      </span>
      <%= if @code do %>
        <span class={[
          "font-mono text-token-2xs font-bold",
          if(@highlighted,
            do: "text-primary-500 dark:text-primary-400",
            else: "text-neutral-500 dark:text-twilight-indigo-300"
          )
        ]}>
          {@code}
        </span>
      <% end %>
    </div>
    """
  end
end
