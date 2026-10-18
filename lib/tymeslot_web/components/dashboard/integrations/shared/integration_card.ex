defmodule TymeslotWeb.Components.Dashboard.Integrations.Shared.IntegrationCard do
  @moduledoc """
  The one card every connected integration renders as: calendar and video
  connections, the automation channels (webhooks, Slack, Telegram) and the
  Stripe account behind payments.

  Top to bottom:

    * a header with a status-tinted icon tile, the title (plus an optional type
      tag) and its status pill, a one-line summary, and the on/off switch
      pinned to the top-right corner;
    * optional details: event tags, a last-activity line and a notice saying
      what needs the owner's attention;
    * a footer action bar, `:actions` on the left and `:end_actions` (edit,
      delete and the like) pushed to the right.

  On a phone the switch stays in the header beside the title instead of
  dropping onto its own line, the pill wraps under a long title, the summary
  wraps instead of being cut off (it truncates from `sm` up, with the full text
  as its hover title), and the footer wraps as a row rather than stacking.

  The card is stateless: the switch pushes `toggle_event` with
  `phx-value-id={@id}` to `target`, and every action is the caller's own
  markup.
  """
  use TymeslotWeb, :html

  alias TymeslotWeb.Components.CoreComponents.Feedback
  alias TymeslotWeb.Components.UI.StatusSwitch

  # The icon tile carries the status pill's colour, so a card reads at a glance
  # even before the pill is read.
  @tones [:brand, :success, :warning, :danger, :info, :neutral]

  @notice_classes %{
    neutral: "text-neutral-600 dark:text-neutral-300",
    warning: "text-amber-700 dark:text-amber-200",
    danger: "text-red-600"
  }

  attr :id, :string, required: true, doc: "The record's id, sent with the toggle as `id`"
  attr :title, :string, required: true

  attr :status, :any,
    required: true,
    doc: "`{tone, label}`: a `pill/1` tone and the pill's text"

  attr :pulse, :boolean, default: false, doc: "Animate the status dot (an awaited step)"
  attr :type_tag, :string, default: nil, doc: "A short descriptor shown beside the title"
  attr :summary, :string, default: nil
  attr :summary_mono, :boolean, default: false, doc: "Set the summary in monospace (URLs, ids)"
  attr :active, :boolean, default: true, doc: "The switch's state; false de-emphasises the card"

  attr :toggle_event, :string,
    default: nil,
    doc: "The event the switch pushes; no switch is shown without one"

  attr :toggle_id, :string, default: nil, doc: "The switch's DOM id; defaults to `toggle-<id>`"

  attr :toggle_disabled, :boolean,
    default: false,
    doc: "Shows the switch but refuses a change, e.g. at an activation limit"

  attr :target, :any, default: nil
  attr :tags, :list, default: [], doc: "Event names shown as chips"
  attr :notice, :string, default: nil, doc: "What needs the owner's attention"
  attr :notice_tone, :atom, default: :warning, values: [:neutral, :warning, :danger]

  attr :heading_level, :integer,
    default: 3,
    values: [2, 3],
    doc:
      "The title's heading level: 3 under a group heading, 2 when the card sits under the page title"

  attr :class, :any, default: nil, doc: "Layout classes only"
  attr :rest, :global

  slot :icon, required: true, doc: "The provider's icon, sized to fit a 44px tile"

  slot :last_activity, doc: "When it last did something; shown after a clock icon" do
    attr :muted, :boolean, doc: "Grey italics, for a never-used integration"
  end

  slot :title_badges, doc: "Markers shown beside the title, after the type tag"
  slot :actions, doc: "The footer's leading actions"
  slot :end_actions, doc: "The footer's trailing actions, pushed to the right"

  @spec integration_card(map()) :: Phoenix.LiveView.Rendered.t()
  def integration_card(%{status: {tone, label}} = assigns)
      when tone in @tones and is_binary(label) do
    assigns =
      assign(assigns,
        tone: tone,
        status_label: label,
        tile_class: Feedback.pill_tone_class(tone),
        notice_class: Map.fetch!(@notice_classes, assigns.notice_tone),
        toggle_id: assigns.toggle_id || "toggle-#{assigns.id}",
        summary: present(assigns.summary),
        footer?: assigns.actions != [] or assigns.end_actions != []
      )

    ~H"""
    <%!-- The tighter padding lets a phone keep the footer on one row. --%>
    <.card
      padding={:sm}
      class={["sm:p-5 transition-opacity", !@active && "opacity-70", @class]}
      {@rest}
    >
      <div class="flex items-start gap-3 sm:gap-4">
        <div class={[
          "flex h-11 w-11 shrink-0 items-center justify-center rounded-token-xl",
          @tile_class
        ]}>
          {render_slot(@icon)}
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
            <.dynamic_tag
              tag_name={"h#{@heading_level}"}
              class={[
                "min-w-0 break-words font-semibold text-neutral-900 dark:text-neutral-50",
                if(@heading_level == 2, do: "text-token-lg", else: "text-token-base")
              ]}
            >
              {@title}
            </.dynamic_tag>
            <span
              :if={@type_tag}
              data-part="type-tag"
              class="rounded-token-sm bg-neutral-100 px-1.5 py-0.5 text-token-xs font-semibold uppercase text-neutral-500 dark:bg-twilight-indigo-800 dark:text-twilight-indigo-300"
            >
              {@type_tag}
            </span>
            {render_slot(@title_badges)}
            <.pill tone={@tone} dot pulse={@pulse}>{@status_label}</.pill>
          </div>
          <p
            :if={@summary}
            data-part="summary"
            title={@summary}
            class={[
              "mt-0.5 break-words text-token-sm text-neutral-500 sm:truncate dark:text-twilight-indigo-300",
              @summary_mono && "font-mono"
            ]}
          >
            {@summary}
          </p>
        </div>

        <StatusSwitch.status_switch
          :if={@toggle_event}
          id={@toggle_id}
          checked={@active}
          on_change={@toggle_event}
          target={@target}
          phx-value-id={@id}
          aria_label={@title}
          disabled={@toggle_disabled}
          class="shrink-0"
        />
      </div>

      <div :if={@tags != []} class="mt-3 flex flex-wrap gap-1.5">
        <span
          :for={tag <- @tags}
          data-part="tag"
          class={[
            "inline-flex items-center gap-1.5 rounded-token-lg border px-2 py-0.5 text-token-xs font-bold",
            (@active &&
               "border-primary-200 bg-primary-50 text-primary-700 dark:border-primary-800 dark:bg-primary-950/40 dark:text-primary-200") ||
              "border-neutral-200 bg-neutral-100 text-neutral-500 dark:border-twilight-indigo-800 dark:bg-twilight-indigo-800 dark:text-twilight-indigo-300"
          ]}
        >
          <span
            class={[
              "h-1.5 w-1.5 rounded-token-full",
              (@active && "bg-primary-500") || "bg-neutral-400"
            ]}
            aria-hidden="true"
          ></span>
          {tag}
        </span>
      </div>

      <div
        :for={activity <- @last_activity}
        data-part="last-activity"
        data-muted={activity[:muted] && "true"}
        class={[
          "mt-3 flex items-center gap-2 text-token-sm",
          (activity[:muted] && "italic text-neutral-400 dark:text-twilight-indigo-300") ||
            "text-neutral-500 dark:text-twilight-indigo-300"
        ]}
      >
        <.icon name="hero-clock" class="h-4 w-4 shrink-0" />
        <span class="min-w-0">{render_slot(activity)}</span>
      </div>

      <p
        :if={@notice}
        data-part="notice"
        data-tone={@notice_tone}
        class={["mt-2 text-token-sm font-medium", @notice_class]}
      >
        {@notice}
      </p>

      <div
        :if={@footer?}
        data-part="footer"
        class="mt-4 flex flex-wrap items-center gap-2 border-t border-neutral-100 pt-3 dark:border-twilight-indigo-800"
      >
        {render_slot(@actions)}
        <div :if={@end_actions != []} data-part="end-actions" class="ml-auto flex items-center gap-2">
          {render_slot(@end_actions)}
        </div>
      </div>
    </.card>
    """
  end

  @doc """
  Classes for a footer action that carries a text label as well as an icon, so
  it cannot be `icon_button/1`: it takes that tile look (the `.icon-button`
  colour rules set no size or padding) and the small action button's size, so
  it sits level with the icon buttons in the footer.
  """
  @spec action_tile_class(:neutral | :warning) :: [String.t()]
  def action_tile_class(variant),
    do: ["icon-button", "icon-button--#{variant}", "gap-1.5 px-3 py-1.5 text-token-sm font-bold"]

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(text) when is_binary(text), do: text
end
