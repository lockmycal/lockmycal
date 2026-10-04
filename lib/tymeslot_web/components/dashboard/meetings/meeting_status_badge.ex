defmodule TymeslotWeb.Components.Dashboard.Meetings.MeetingStatusBadge do
  @moduledoc """
  The one badge that says what state a booking is in.

  Split out of `MeetingListComponents` when the approval gate added a fifth
  state, because the states are mutually exclusive: a held request that also
  matches "not cancelled and not past" must not render as both "Awaiting your
  approval" and "Scheduled", which is precisely the contradiction this feature
  exists to remove.

  Used to be sibling `:if` clauses, each repeating every other state's
  negation as a guard. That shape silently swallowed `"expired"`: it matched
  none of the guards, so it fell through to the last (unguarded-by-status)
  clause and rendered "Scheduled". `badge_variant/1` below names every status
  in `Tymeslot.Meetings.MeetingSchema`'s valid list either its own explicit
  clause or the time-derived split (scheduled vs completed, the only pair
  that genuinely depends on the clock rather than the status column). Only a
  status this module has never heard of falls through the final `true` case.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Meetings.MeetingState
  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers

  @typep variant ::
           :cancelled
           | :expired
           | :awaiting_new_time
           | :awaiting_approval
           | :awaiting_payment
           | :completed
           | :scheduled

  @base_classes "inline-flex items-center gap-1.5 px-3 py-1 text-token-xs font-black uppercase tracking-wider rounded-full border shadow-sm"

  attr :meeting, :map, required: true

  attr :organizer?, :boolean,
    default: true,
    doc: "false for a booking the viewer made as its attendee, whose request awaits the host"

  @spec status_badges(map()) :: Phoenix.LiveView.Rendered.t()
  def status_badges(assigns) do
    variant = badge_variant(assigns.meeting)

    assigns =
      assign(assigns,
        classes: badge_classes(variant),
        icon: badge_icon(variant),
        label: badge_label(variant, assigns.organizer?)
      )

    ~H"""
    <span class={@classes}>
      <CoreComponents.icon name={@icon} class="w-3 h-3" /> {@label}
    </span>
    """
  end

  # Cancelled, expired, awaiting payment and completed are read straight off
  # `status`: all four are terminal or Stripe-driven and none is contingent
  # on the meeting's time — an unpaid checkout badged "Scheduled" is the
  # "unconfirmed thing shown as agreed" failure this feature exists to
  # remove, one status over. Everything else derives from the
  # live/awaiting/past shape, in priority order; "pending" and "confirmed"
  # both fall to the time-derived split deliberately, since neither implies
  # anything beyond it.
  @spec badge_variant(map()) :: variant()
  defp badge_variant(%{status: "cancelled"}), do: :cancelled
  defp badge_variant(%{status: "expired"}), do: :expired
  defp badge_variant(%{status: "awaiting_payment"}), do: :awaiting_payment
  defp badge_variant(%{status: "completed"}), do: :completed

  defp badge_variant(meeting) do
    cond do
      MeetingState.awaiting_new_time?(meeting) -> :awaiting_new_time
      MeetingState.awaiting_approval?(meeting) -> :awaiting_approval
      Helpers.past_meeting?(meeting) -> :completed
      true -> :scheduled
    end
  end

  @spec badge_classes(variant()) :: String.t()
  defp badge_classes(:cancelled),
    do:
      @base_classes <>
        " bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300 border-red-100 dark:border-red-800"

  defp badge_classes(:expired),
    do: @base_classes <> " bg-tymeslot-100 text-tymeslot-500 border-tymeslot-200"

  defp badge_classes(:awaiting_new_time),
    do:
      @base_classes <>
        " bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300 border-amber-100 dark:border-amber-800"

  defp badge_classes(:awaiting_approval),
    do:
      @base_classes <>
        " bg-amber-50 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300 border-amber-100 dark:border-amber-800"

  defp badge_classes(:awaiting_payment),
    do: @base_classes <> " bg-amber-50 text-amber-700 border-amber-100"

  defp badge_classes(:completed),
    do:
      @base_classes <>
        " bg-neutral-100 dark:bg-twilight-indigo-900 text-neutral-600 dark:text-neutral-400 border-neutral-300 dark:border-twilight-indigo-700"

  defp badge_classes(:scheduled),
    do:
      @base_classes <>
        " bg-emerald-50 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300 border-emerald-100 dark:border-emerald-800"

  @spec badge_icon(variant()) :: String.t()
  defp badge_icon(:cancelled), do: "hero-x-mark"
  defp badge_icon(:expired), do: "hero-clock"
  defp badge_icon(:awaiting_new_time), do: "hero-clock"
  defp badge_icon(:awaiting_approval), do: "hero-inbox-arrow-down"
  defp badge_icon(:awaiting_payment), do: "hero-credit-card"
  defp badge_icon(:completed), do: "hero-check"
  defp badge_icon(:scheduled), do: "hero-calendar-days"

  @spec badge_label(variant(), boolean()) :: String.t()
  defp badge_label(:awaiting_approval, false = _organizer?),
    do: dgettext("dashboard_bookings", "Awaiting host approval")

  defp badge_label(variant, _organizer?), do: badge_label(variant)

  @spec badge_label(variant()) :: String.t()
  defp badge_label(:cancelled), do: dgettext("dashboard_bookings", "Cancelled")
  defp badge_label(:expired), do: dgettext("dashboard_bookings", "Expired")
  defp badge_label(:awaiting_new_time), do: dgettext("dashboard_bookings", "Reschedule Requested")

  defp badge_label(:awaiting_approval),
    do: dgettext("dashboard_bookings", "Awaiting your approval")

  defp badge_label(:awaiting_payment),
    do: dgettext("dashboard_bookings", "Awaiting payment")

  defp badge_label(:completed), do: dgettext("dashboard_bookings", "Completed")
  defp badge_label(:scheduled), do: dgettext("dashboard_bookings", "Scheduled")
end
