defmodule TymeslotWeb.Components.Dashboard.Availability.ScheduleAccents do
  @moduledoc """
  The colour each availability schedule's chip is drawn in on the meeting-type
  form.

  The availability page itself no longer wears a per-schedule colour (it
  follows the same flat, uncoloured layout as the rest of the dashboard), but
  the meeting-type form's schedule chips still need one colour per schedule so
  they stay visually distinct from each other in that list.

  Assigned by position in the profile's schedule list, which callers get from
  `Tymeslot.Availability.Schedules.list_for_profile/1`. The list is as long as
  the schedule cap; `rem/2` keeps `at/1` total should that cap ever rise.
  """

  @accents [
    "bg-primary-500",
    "bg-violet-500",
    "bg-amber-500",
    "bg-emerald-500",
    "bg-blue-500"
  ]

  @doc "The dot colour class at a position in the schedule list."
  @spec at(non_neg_integer()) :: String.t()
  def at(index), do: Enum.at(@accents, rem(index, length(@accents)))
end
