defmodule TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.SharedClampEndTimeTest do
  @moduledoc """
  Unit tests for `Shared.clamp_end_time/3`, pinning the fix for a day-boundary
  bug in `CreateFormState.handle_show_create_form/2`'s "no time params"
  clause (the `c` keyboard shortcut) and `BookingsManagement.QuickAddMeeting
  .default_creating_event/1`: both compute a default one-hour slot as
  `start_hour`/`rem(start_hour + 1, 24)`, and when that default slot starts
  at 23:00, `rem/2` wraps the end hour back to 0 while `end_date` stayed on
  the same day, producing an end time before the start time and blocking the
  create-event dialog entirely for that hour. Both now pass the *unwrapped*
  `start_hour + 1` (can be 24) through `clamp_end_time/3` instead, which
  rolls `end_date` to the next day whenever the hour needs wrapping.
  """

  use ExUnit.Case, async: true

  @moduletag :unit
  @moduletag :calendar

  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared

  describe "clamp_end_time/3" do
    test "passes an in-range hour through unchanged" do
      assert Shared.clamp_end_time(~D[2026-08-16], 10, 30) == {~D[2026-08-16], 10, 30}
    end

    test "an hour of exactly 23 needs no rollover" do
      assert Shared.clamp_end_time(~D[2026-08-16], 23, 0) == {~D[2026-08-16], 23, 0}
    end

    test "rolls the date to the next day when the hour is 24 (the 23:00 default-slot case)" do
      assert Shared.clamp_end_time(~D[2026-08-16], 24, 0) == {~D[2026-08-17], 0, 0}
    end

    test "preserves the minute across a rollover" do
      assert Shared.clamp_end_time(~D[2026-08-16], 24, 45) == {~D[2026-08-17], 0, 45}
    end
  end
end
