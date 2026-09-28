defmodule TymeslotWeb.Dashboard.CalendarGrid.Views.MonthViewTest do
  use ExUnit.Case, async: true

  @moduletag :calendar

  import Phoenix.LiveViewTest

  alias Tymeslot.Integrations.Calendar.EventColour
  alias TymeslotWeb.Dashboard.CalendarGrid.Views.MonthView

  # Month of April 2026, rendered as a 6×7 matrix starting Monday 30 March.
  @visible_days Enum.map(0..41, &Date.add(~D[2026-03-30], &1))

  defp base_assigns(events) do
    %{
      view: :month,
      visible_days: @visible_days,
      visible_events: events,
      integrations: [],
      integration_colors: %{1 => EventColour.rotation_class(1)},
      calendar_colors: %{},
      hidden_integration_ids: [],
      date: ~D[2026-04-15],
      user_timezone: "Etc/UTC",
      preferences: nil,
      guest_rsvp_summaries: %{},
      myself: nil
    }
  end

  # visible_events are cache-row structs in production; a plain map with the
  # same fields is enough to exercise the layout + render path.
  defp event(fields) do
    Map.merge(
      %{
        id: nil,
        summary: nil,
        all_day: false,
        start_date: nil,
        end_date: nil,
        start_at: nil,
        end_at: nil,
        calendar_integration_id: 1,
        colour: nil,
        created_by_tymeslot: false
      },
      fields
    )
  end

  defp all_day_event(id, summary, start_date, end_date) do
    event(%{id: id, summary: summary, all_day: true, start_date: start_date, end_date: end_date})
  end

  defp timed_event(id, summary, start_at, end_at) do
    event(%{id: id, summary: summary, start_at: start_at, end_at: end_at})
  end

  test "all-day events render in the month grid (regression: they used to be dropped)" do
    events = [all_day_event(1, "Conference", ~D[2026-04-07], ~D[2026-04-10])]

    html = render_component(&MonthView.month_view/1, base_assigns(events))

    assert html =~ "Conference"
    # Rendered as a spanning bar (pointer-events-auto re-enables clicks on the bar).
    assert html =~ "pointer-events-auto"
    assert html =~ ~s(phx-value-event-id="1")
  end

  test "overlapping multi-day events are packed into separate lanes" do
    events = [
      all_day_event(1, "Conference", ~D[2026-04-07], ~D[2026-04-10]),
      timed_event(2, "Travel", ~U[2026-04-07 22:00:00Z], ~U[2026-04-09 02:00:00Z])
    ]

    html = render_component(&MonthView.month_view/1, base_assigns(events))

    assert html =~ "Conference"
    assert html =~ "Travel"
    # Two lanes: the first bar sits at the band top, the second one lane below.
    assert html =~ "top: 1.75rem"
    assert html =~ "top: 2.75rem"
  end

  test "single-day timed events render as chips, not bars" do
    events = [timed_event(3, "Lunch", ~U[2026-04-08 11:00:00Z], ~U[2026-04-08 12:00:00Z])]

    html = render_component(&MonthView.month_view/1, base_assigns(events))

    assert html =~ "Lunch"
    # A lone single-day event needs no bar lane, so no spanning-bar overlay.
    refute html =~ "pointer-events-auto"
  end

  test "a bar's summary span carries min-w-0 so a long title truncates instead of overflowing the bar" do
    # Regression: the summary `<span>` is a flex child of the bar's `flex
    # items-center` container. Without `min-w-0`, a flex item's default
    # `min-width: auto` lets a long summary's intrinsic width win over the
    # bar's fixed `calc()` width, so `truncate` never engages and the text
    # visually spills past the bar's right edge into the next day's column
    # (TODO #31 — reproduced on a real account with long all-day event
    # titles; short test-data titles never hit the overflow).
    events = [
      all_day_event(
        1,
        "Penzion Chlupy U Smrku má výročí",
        ~D[2026-04-07],
        ~D[2026-04-09]
      )
    ]

    html = render_component(&MonthView.month_view/1, base_assigns(events))

    assert html =~ ~s(<span class="truncate min-w-0">Penzion Chlupy U Smrku má výročí</span>)
  end

  test "the day-of-week header row and the day-cell grid opt out of the legacy .grid gap" do
    # Regression: `assets/css/layout/utilities.css` has a hand-rolled
    # `.grid { gap: var(--spacing-4) }` (16px) in `@layer components`. Tailwind's
    # own `.grid` utility (`@layer utilities`) never declares `gap` at all, so
    # there is no competing declaration for cascade-layer order to resolve —
    # the legacy rule wins unopposed on any bare `.grid` element. That silently
    # widened every day column's gap beyond what `bar_style/1`'s 1/7-fraction
    # math accounts for, so every spanning bar rendered wider than its day cell
    # and bled into the next column (TODO #31). Both `.grid` elements here need
    # an explicit `gap-0` to opt back out of it.
    html = render_component(&MonthView.month_view/1, base_assigns([]))

    assert html =~
             ~s(class="grid gap-0 border-b border-neutral-300 dark:border-twilight-indigo-800 bg-tertiary-100)

    assert html =~ ~s(<div class="grid grid-cols-7 gap-0">)
  end
end
