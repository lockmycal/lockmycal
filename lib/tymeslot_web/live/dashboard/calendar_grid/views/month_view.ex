defmodule TymeslotWeb.Dashboard.CalendarGrid.Views.MonthView do
  @moduledoc "Month grid view function component for the calendar grid."

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Dashboard.Meetings.AttendeeAttachments
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers
  alias TymeslotWeb.Dashboard.CalendarGrid.Views.EventBadges
  alias TymeslotWeb.Helpers.LocaleFormat

  # Vertical rhythm for the bar band, in rem. The day number occupies the top
  # `@band_top` — this must clear it (offset `top-1` = 0.25rem plus a
  # `text-token-sm` line), or the first lane's bar overlaps the date digits. Each multi-day/
  # all-day bar lane is `@lane_h` tall with the bar itself `@bar_h`. Single-day
  # chips are pushed below the reserved lane band.
  @band_top 1.75
  @lane_h 1.0
  @bar_h 0.9

  attr :view, :atom, required: true
  attr :visible_days, :list, required: true
  attr :visible_events, :list, required: true
  attr :integrations, :list, required: true
  attr :integration_colors, :map, required: true
  attr :calendar_colors, :map, required: true
  attr :hidden_integration_ids, :list, required: true
  attr :date, :any, required: true
  attr :user_timezone, :string, required: true
  attr :preferences, :any
  attr :guest_rsvp_summaries, :map, default: %{}
  attr :myself, :any, required: true

  @spec month_view(map()) :: Phoenix.LiveView.Rendered.t()
  def month_view(assigns) do
    ~H"""
    <div
      id="calendar-month-grid"
      class={if @view == :month, do: "flex-1 overflow-auto pr-2 md:pr-3", else: "hidden"}
    >
      <%!-- Day-of-week headers --%>
      <div
        class="grid gap-0 border-b border-neutral-300 dark:border-twilight-indigo-800 bg-tertiary-100 dark:bg-twilight-indigo-900 sticky top-0 z-10"
        style={
          if Helpers.show_week_numbers?(assigns),
            do: "grid-template-columns: 2rem repeat(7, 1fr)",
            else: "grid-template-columns: repeat(7, 1fr)"
        }
      >
        <div
          :if={Helpers.show_week_numbers?(assigns)}
          class="text-center text-token-xs font-semibold text-neutral-500 dark:text-neutral-400 py-1 sm:py-2"
        >
          {dgettext("dashboard_calendar", "Wk")}
        </div>
        <div
          :for={day_name <- Helpers.day_name_headers(assigns)}
          class="text-center text-token-xs font-semibold text-neutral-600 dark:text-neutral-300 py-1 sm:py-2 uppercase tracking-wide"
        >
          <span class="hidden sm:inline">{day_name}</span>
          <span class="sm:hidden">{String.first(day_name)}</span>
        </div>
      </div>

      <%!-- One row per week (keyed on month to retrigger fade on navigation).
            Each week is its own positioning context so multi-day / all-day bars
            can span its day columns. --%>
      <div
        id={"month-grid-#{@date.year}-#{@date.month}"}
        class="animate-fade-in border-l border-t border-neutral-300 dark:border-twilight-indigo-800"
      >
        <.month_week
          :for={week_days <- Enum.chunk_every(@visible_days, 7)}
          week_days={week_days}
          assigns_ref={assigns}
          user_timezone={@user_timezone}
          myself={@myself}
        />
      </div>
    </div>
    """
  end

  attr :week_days, :list, required: true
  attr :assigns_ref, :map, required: true
  attr :user_timezone, :string, required: true
  attr :myself, :any, required: true

  defp month_week(assigns) do
    layout = Helpers.week_layout(assigns.assigns_ref, assigns.week_days)

    assigns =
      assigns
      |> assign(:segments, layout.segments)
      |> assign(:indexed_days, Enum.with_index(assigns.week_days))

    ~H"""
    <div class="flex">
      <div
        :if={Helpers.show_week_numbers?(@assigns_ref)}
        class="w-8 shrink-0 text-token-xs font-medium text-neutral-500 dark:text-neutral-400 flex items-start justify-center pt-1 border-b border-r border-neutral-300 dark:border-twilight-indigo-800"
      >
        {Helpers.week_number(List.first(@week_days))}
      </div>

      <div class="relative flex-1">
        <%!-- Day cells (define the row height). Each cell only reserves band
              space for the lanes its own bars actually use — not the row's
              shared maximum — so a day with fewer (or no) bars than its
              neighbours doesn't push its chips down to match them. --%>
        <%!-- `gap-0`: a legacy hand-rolled `.grid { gap: var(--spacing-4) }` rule
              (assets/css/layout/utilities.css, @layer components) sets a 16px
              gap on every bare `.grid` element, because Tailwind's own `.grid`
              utility doesn't declare `gap` at all — so there's no competing
              utilities-layer declaration to win by layer order, and the legacy
              rule applies unopposed. Without an explicit `gap-0` here, the
              7 day cells render narrower than 1/7 of the row (gaps eat into
              the available width), while `bar_style/1` below still computes
              each spanning bar's left/width as a clean 1/7 fraction — so every
              bar renders wider than its day cell and bleeds into the next
              column (TODO #31). --%>
        <div class="grid grid-cols-7 gap-0">
          <.month_cell
            :for={{day, idx} <- @indexed_days}
            day={day}
            assigns_ref={@assigns_ref}
            cell_lane_count={day_lane_count(@segments, idx)}
            user_timezone={@user_timezone}
            myself={@myself}
          />
        </div>

        <%!-- Spanning bars overlaid across the week's columns. The layer ignores
              pointer events so empty band area still navigates the cell beneath;
              each bar re-enables them to open the event. --%>
        <div class="absolute inset-0 pointer-events-none">
          <div
            :for={seg <- @segments}
            class={"absolute px-1 flex items-center text-token-xs truncate cursor-pointer pointer-events-auto #{bar_round_class(seg)} #{Helpers.event_block_class(@assigns_ref, seg.event)}"}
            style={bar_style(seg)}
            {Helpers.open_event_attrs(seg.event)}
            phx-target={@myself}
            title={
              "#{seg.event.summary || dgettext("dashboard_calendar", "(No title)")} · #{Helpers.format_display_time_range(seg.event, Helpers.time_format(@assigns_ref), @assigns_ref.user_timezone)}"
            }
          >
            <img
              :if={Map.get(seg.event, :created_by_tymeslot)}
              src="/images/brand/logo.svg"
              alt=""
              class="inline-block w-3 h-3 opacity-70 mr-0.5 shrink-0"
            /><%!-- `min-w-0` overrides the flex item's default `min-width: auto`,
                  which otherwise lets a long summary's intrinsic width win over
                  the bar's fixed `calc()` width and spill past its right edge
                  into the next day's column instead of truncating. --%><span class="truncate min-w-0">{seg.event.summary ||
              dgettext("dashboard_calendar", "(No title)")}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :day, :any, required: true
  attr :assigns_ref, :map, required: true
  attr :cell_lane_count, :integer, required: true
  attr :user_timezone, :string, required: true
  attr :myself, :any, required: true

  defp month_cell(assigns) do
    chips = Helpers.chip_events(assigns.assigns_ref, assigns.day)

    is_current_month = assigns.day.month == assigns.assigns_ref.date.month

    assigns =
      assigns
      |> assign(:chips, chips)
      |> assign(:is_current_month, is_current_month)
      |> assign(:locale, Gettext.get_locale(TymeslotWeb.Gettext))

    ~H"""
    <div
      class={"relative min-w-0 min-h-12 sm:min-h-20 border-b border-r border-neutral-300 dark:border-twilight-indigo-800 p-1 cursor-pointer hover:bg-neutral-50 dark:hover:bg-twilight-indigo-900/40 focus:outline-hidden focus:ring-2 focus:ring-primary-400 focus:ring-inset #{Helpers.month_cell_class(@day, @assigns_ref)}"}
      style={cell_padding_top(@cell_lane_count)}
      phx-click="navigate_to_day"
      phx-value-date={Date.to_iso8601(@day)}
      phx-target={@myself}
      role="button"
      tabindex="0"
      aria-label={
        LocaleFormat.format_weekday_day_month(@day, @locale) <>
          ", " <>
          dngettext(
            "dashboard_calendar",
            "%{count} event",
            "%{count} events",
            length(@chips),
            count: length(@chips)
          )
      }
    >
      <div class={"absolute top-1 left-1 text-token-sm font-semibold #{day_number_class(@is_current_month)}"}>
        {@day.day}
      </div>

      <%!-- Desktop: up to 3 single-day event titles --%>
      <div class="hidden sm:block">
        <div
          :for={event <- Enum.take(@chips, 3)}
          class={"rounded px-1 text-token-xs truncate mb-0.5 cursor-pointer #{Helpers.event_block_class(@assigns_ref, event)}"}
          {Helpers.open_event_attrs(event)}
          phx-target={@myself}
          title={
            "#{event.summary || dgettext("dashboard_calendar", "(No title)")} · #{Helpers.format_display_time_range(event, Helpers.time_format(@assigns_ref), @assigns_ref.user_timezone)}"
          }
        >
          <img
            :if={Map.get(event, :created_by_tymeslot)}
            src="/images/brand/logo.svg"
            alt=""
            class="inline-block w-3 h-3 opacity-60 mr-0.5 align-text-bottom"
          /><AttendeeAttachments.marker attachments={Map.get(event, :attendee_attachments)} />{event.summary ||
            dgettext("dashboard_calendar", "(No title)")}<span
            :if={EventBadges.guest_summary_for_event(@assigns_ref.guest_rsvp_summaries, event)}
            class={[
              "inline-block w-1.5 h-1.5 rounded-full ml-0.5 align-middle",
              EventBadges.guest_dot_tone(
                EventBadges.guest_summary_for_event(@assigns_ref.guest_rsvp_summaries, event)
              )
            ]}
            title={
              EventBadges.guest_badge_title(
                EventBadges.guest_summary_for_event(@assigns_ref.guest_rsvp_summaries, event)
              )
            }
          ></span>
        </div>
        <div
          :if={length(@chips) > 3}
          class="text-token-xs font-medium text-neutral-500 dark:text-neutral-400 mt-0.5"
        >
          {dngettext("dashboard_calendar", "+%{count} more", "+%{count} more", length(@chips) - 3,
            count: length(@chips) - 3
          )}
        </div>
      </div>

      <%!-- Mobile: first single-day title + coloured chip with count --%>
      <div class="sm:hidden flex flex-col gap-0.5">
        <div
          :if={List.first(@chips)}
          class={"rounded px-1 text-token-xs truncate #{Helpers.event_block_class(@assigns_ref, List.first(@chips))}"}
        >
          {List.first(@chips).summary || dgettext("dashboard_calendar", "(No title)")}
        </div>
        <div
          :if={length(@chips) > 1}
          class="inline-flex items-center gap-0.5 text-token-2xs text-neutral-500 dark:text-neutral-400 leading-none"
        >
          <span
            :for={event <- @chips |> Enum.drop(1) |> Enum.take(3)}
            class={"w-1.5 h-1.5 rounded-full #{Helpers.event_dot_class(@assigns_ref, event)}"}
          ></span>
          <span :if={length(@chips) > 4} class="ml-0.5">+{length(@chips) - 4}</span>
        </div>
      </div>
    </div>
    """
  end

  # Reserve vertical room above the chips for the lanes this cell's own bars
  # occupy.
  defp cell_padding_top(lane_count) do
    "padding-top: #{@band_top + lane_count * @lane_h}rem"
  end

  # The number of lanes actually used by bars touching column `col_idx`
  # (0-6) — i.e. one past the highest lane index among segments spanning
  # that day, or 0 when no bar touches it at all.
  defp day_lane_count(segments, col_idx) do
    lanes =
      segments
      |> Enum.filter(&(&1.start_col <= col_idx and &1.end_col >= col_idx))
      |> Enum.map(& &1.lane)

    case lanes do
      [] -> 0
      lanes -> Enum.max(lanes) + 1
    end
  end

  # Absolute placement of a spanning bar across the week's 7 columns. Insets
  # 1px off the day-column boundary on whichever ends actually start/finish
  # within this week (mirroring `bar_round_class/1`'s rounding), so two
  # different single-day events in adjacent columns get a visible gap
  # instead of their bars touching edge-to-edge at the shared border — a bar
  # that continues into the next/previous week stays flush there, since
  # there's no neighbouring day to separate from at that end.
  defp bar_style(seg) do
    left_pct = Float.round(seg.start_col * 100 / 7, 4)
    width_pct = Float.round((seg.end_col - seg.start_col + 1) * 100 / 7, 4)
    top = @band_top + seg.lane * @lane_h
    left_inset = if seg.continues_left, do: 0, else: 1
    right_inset = if seg.continues_right, do: 0, else: 1

    "left: calc(#{left_pct}% + #{left_inset}px); width: calc(#{width_pct}% - #{left_inset + right_inset}px); top: #{top}rem; height: #{@bar_h}rem"
  end

  # Round only the ends that actually start/finish within this week; a bar that
  # continues into an adjacent week keeps a flat edge so it reads as continuous.
  defp bar_round_class(%{continues_left: false, continues_right: false}), do: "rounded"
  defp bar_round_class(%{continues_left: true, continues_right: false}), do: "rounded-r"
  defp bar_round_class(%{continues_left: false, continues_right: true}), do: "rounded-l"
  defp bar_round_class(%{continues_left: true, continues_right: true}), do: "rounded-none"

  # Today is told apart by its cell's tint (`Helpers.month_cell_class/2`), not
  # by its number.
  defp day_number_class(false = _is_current_month), do: "text-neutral-400"
  defp day_number_class(_is_current_month), do: "text-neutral-800 dark:text-neutral-200"
end
