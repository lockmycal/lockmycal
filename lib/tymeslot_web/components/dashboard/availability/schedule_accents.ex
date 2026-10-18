defmodule TymeslotWeb.Components.Dashboard.Availability.ScheduleAccents do
  @moduledoc """
  The colour each availability schedule is drawn in.

  Every schedule holds the same shape of data, so colour is what tells them
  apart at a glance: the availability page paints a schedule's tab with its hue
  (the frame around it stays a plain card), and the meeting-type form marks its
  chip with the same one, so a host recognises "the amber schedule" across both.

  The hues are categorical, not semantic, and step outside the brand palette on
  purpose: five schedules need five colours that stay apart at a glance, which
  the turquoise, cyan and neutral scales alone cannot give. Violet and emerald
  are deliberate for that reason; the status colours (green, amber, red, blue)
  keep their meaning elsewhere, and a schedule's colour carries none.

  Assigned by position in the profile's schedule list, which both callers get
  from `Tymeslot.Availability.Schedules.list_for_profile/1` and therefore see in
  the same order. The list is as long as the schedule cap; `rem/2` keeps
  `at/1` total should that cap ever rise.
  """

  @accents [
    %{
      tab: "bg-primary-600 text-white shadow-lg shadow-primary-500/30",
      dot: "bg-primary-500"
    },
    %{
      tab: "bg-violet-600 text-white shadow-lg shadow-violet-500/30",
      dot: "bg-violet-500"
    },
    %{
      tab: "bg-amber-600 text-white shadow-lg shadow-amber-500/30",
      dot: "bg-amber-500"
    },
    %{
      tab: "bg-emerald-600 text-white shadow-lg shadow-emerald-500/30",
      dot: "bg-emerald-500"
    },
    %{
      tab: "bg-blue-600 text-white shadow-lg shadow-blue-500/30",
      dot: "bg-blue-500"
    }
  ]

  @doc "The accent at a position in the schedule list."
  @spec at(non_neg_integer()) :: map()
  def at(index), do: Enum.at(@accents, rem(index, length(@accents)))
end
