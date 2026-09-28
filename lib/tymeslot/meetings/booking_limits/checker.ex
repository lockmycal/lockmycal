defmodule Tymeslot.Meetings.BookingLimits.Checker do
  @moduledoc """
  Wires `Tymeslot.Meetings.BookingLimits` to booking data: fetches the
  relevant slot-occupying bookings once and returns ready-to-use checks.

  When no cap is configured the functions bail out before reading any
  bookings, so hosts without limits pay at most the one small lookup of the
  schedule's per-weekday minute caps.
  """

  alias Tymeslot.Availability.Schedules
  alias Tymeslot.Availability.WeeklyAvailabilityQueries
  alias Tymeslot.Meetings.BookingLimits
  alias Tymeslot.Meetings.MeetingQueries
  alias Tymeslot.Profiles

  @doc """
  Builds a `(DateTime.t() -> boolean())` closure answering "would a booking
  at this instant exceed a limit?" for slots rendered in
  `start_date..end_date`, or `nil` when no cap is configured.

  `profile_settings` is a profile struct or settings map carrying the
  account-wide caps and the host timezone; `meeting_type` carries the
  per-type caps (may be `nil`).

  Options:
    * `:exclude_uid` — omit one meeting from the counts (reschedule self-exclusion).
    * `:duration_minutes` — the candidate booking's length; enables the
      schedule's per-weekday caps on booked minutes.
    * `:schedule` — the availability schedule being booked, when the caller
      has already resolved it. Otherwise it is resolved from `meeting_type`,
      falling back to the host's default schedule.
  """
  @spec build_slot_checker(integer(), map() | nil, map() | nil, Date.t(), Date.t(), keyword()) ::
          (DateTime.t() -> boolean()) | nil
  def build_slot_checker(
        organizer_user_id,
        profile_settings,
        meeting_type,
        start_date,
        end_date,
        opts \\ []
      ) do
    with_context(
      organizer_user_id,
      profile_settings,
      meeting_type,
      start_date,
      end_date,
      opts,
      fn context ->
        &BookingLimits.slot_blocked?(context, &1)
      end
    )
  end

  @doc """
  Booking-time check: whether a booking starting at `start_time` is within
  every configured cap. Returns `:ok` when no cap is configured.

  Accepts the same options as `build_slot_checker/6`, plus:
    * `:before_count` — a zero-arity function run once limits are known to
      apply, before the bookings are read (the booking transaction takes its
      per-host lock here, so hosts without limits never take it).
  """
  @spec check_booking_allowed(integer(), map() | nil, map() | nil, DateTime.t(), keyword()) ::
          :ok | {:error, :booking_limit_reached}
  def check_booking_allowed(
        organizer_user_id,
        profile_settings,
        meeting_type,
        %DateTime{} = start_time,
        opts \\ []
      ) do
    host_timezone = host_timezone(profile_settings)
    day = BookingLimits.day_key(start_time, host_timezone)

    case with_context(
           organizer_user_id,
           profile_settings,
           meeting_type,
           day,
           day,
           opts,
           fn context ->
             BookingLimits.check_booking_allowed(context, start_time)
           end
         ) do
      nil -> :ok
      result -> result
    end
  end

  defp with_context(
         organizer_user_id,
         profile_settings,
         meeting_type,
         start_date,
         end_date,
         opts,
         fun
       ) do
    limits =
      BookingLimits.limits_for(
        profile_settings,
        meeting_type,
        duration_minutes: opts[:duration_minutes],
        daily_minutes: daily_minutes(organizer_user_id, meeting_type, opts)
      )

    if BookingLimits.enabled?(limits) do
      if before_count = opts[:before_count], do: before_count.()

      host_timezone = host_timezone(profile_settings)

      {from_utc, to_utc} =
        BookingLimits.expanded_query_window(start_date, end_date, host_timezone)

      rows =
        MeetingQueries.list_live_booking_starts(
          organizer_user_id,
          from_utc,
          to_utc,
          Keyword.take(opts, [:exclude_uid])
        )

      fun.(BookingLimits.build_context(limits, host_timezone, rows))
    end
  end

  defp daily_minutes(organizer_user_id, meeting_type, opts) do
    if is_integer(opts[:duration_minutes]) do
      schedule =
        Keyword.get_lazy(opts, :schedule, fn ->
          Schedules.resolve_for_meeting_type(meeting_type || %{user_id: organizer_user_id})
        end)

      case schedule do
        %{id: schedule_id} -> WeeklyAvailabilityQueries.daily_booked_minutes_caps(schedule_id)
        nil -> %{}
      end
    else
      %{}
    end
  end

  defp host_timezone(profile_settings) do
    (profile_settings && Map.get(profile_settings, :timezone)) || Profiles.get_default_timezone()
  end
end
