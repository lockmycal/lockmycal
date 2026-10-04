defmodule Tymeslot.FreeBusy do
  @moduledoc """
  Publishes a profile's busy intervals as an iCalendar `VFREEBUSY` feed.

  The feed is exposed at `GET /free-busy/:token`. A profile opts in by
  generating a secret token (`enable_feed/1`); clearing it (`disable_feed/1`)
  takes the feed offline. Busy intervals are derived from the same connected
  calendar events the availability engine treats as blocking, plus the
  profile's time off, so a holiday entered in Tymeslot rather than in a
  calendar is published as busy too.
  """

  alias Tymeslot.Availability.TimeOff
  alias Tymeslot.Integrations.Calendar.CalendarEvent
  alias Tymeslot.Integrations.Calendar.CalendarEventQueries
  alias Tymeslot.Integrations.Calendar.CalendarIntegrationQueries
  alias Tymeslot.Integrations.Calendar.FreebusyGenerator
  alias Tymeslot.Meetings
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Profiles.ProfileSchema
  alias Tymeslot.Utils.DateTimeUtils

  @token_bytes 24
  @default_horizon_days 60

  @doc "Returns the profile owning `token`, or `{:error, :not_found}`."
  @spec get_profile_by_token(String.t()) :: {:ok, ProfileSchema.t()} | {:error, :not_found}
  def get_profile_by_token(token), do: ProfileQueries.get_by_freebusy_token(token)

  @doc "Whether the profile has an active free/busy feed."
  @spec feed_enabled?(ProfileSchema.t()) :: boolean()
  def feed_enabled?(%ProfileSchema{freebusy_token: token}),
    do: is_binary(token) and token != ""

  @doc """
  Ensures the profile has a feed token, generating one if absent. Idempotent —
  an already-enabled feed keeps its existing token.
  """
  @spec enable_feed(ProfileSchema.t()) ::
          {:ok, ProfileSchema.t()} | {:error, Ecto.Changeset.t()}
  def enable_feed(%ProfileSchema{} = profile) do
    if feed_enabled?(profile) do
      {:ok, profile}
    else
      ProfileQueries.update_freebusy_token(profile, generate_token())
    end
  end

  @doc "Issues a fresh token, invalidating any previously shared feed URL."
  @spec regenerate_token(ProfileSchema.t()) ::
          {:ok, ProfileSchema.t()} | {:error, Ecto.Changeset.t()}
  def regenerate_token(%ProfileSchema{} = profile),
    do: ProfileQueries.update_freebusy_token(profile, generate_token())

  @doc "Disables the feed by clearing the token."
  @spec disable_feed(ProfileSchema.t()) ::
          {:ok, ProfileSchema.t()} | {:error, Ecto.Changeset.t()}
  def disable_feed(%ProfileSchema{} = profile),
    do: ProfileQueries.update_freebusy_token(profile, nil)

  @doc """
  Renders the `VFREEBUSY` document for the profile over a rolling window
  (`now` → `now + horizon_days`, default #{@default_horizon_days}).
  """
  @spec feed(ProfileSchema.t(), keyword()) :: String.t()
  def feed(%ProfileSchema{} = profile, opts \\ []) do
    horizon_days = Keyword.get(opts, :horizon_days, @default_horizon_days)
    window_start = DateTime.truncate(Keyword.get(opts, :now, DateTime.utc_now()), :second)
    window_end = DateTime.add(window_start, horizon_days, :day)

    FreebusyGenerator.generate(
      uid: "freebusy-#{profile.id}@tymeslot.com",
      window_start: window_start,
      window_end: window_end,
      organizer_email: organizer_email(profile),
      intervals: busy_intervals(profile, window_start, window_end)
    )
  end

  @doc """
  Returns the profile's busy intervals (UTC `{start, end}` pairs) overlapping
  the window, derived from connected-calendar events that block availability
  and from the profile's time off. Birthday/anniversary reminder events are
  excluded (see `CalendarEvent.reminder?/1`) — they sync in as opaque
  all-day events but aren't real unavailability.
  """
  @spec busy_intervals(ProfileSchema.t(), DateTime.t(), DateTime.t()) ::
          [FreebusyGenerator.interval()]
  def busy_intervals(%ProfileSchema{} = profile, window_start, window_end) do
    event_intervals =
      profile
      |> busy_intervals_with_source(window_start, window_end)
      |> Enum.map(fn {start_at, end_at, _calendar_integration_id} -> {start_at, end_at} end)

    event_intervals ++
      TimeOff.busy_intervals(profile.id, profile.timezone, window_start, window_end)
  end

  @doc """
  Same as `busy_intervals/3`, but each interval also carries the
  `calendar_integration_id` it came from — used by the public calendar page
  to colour busy blocks per source calendar when the organiser has opted
  into `ProfileSchema.public_calendar_colors`. Not used by the VFREEBUSY
  feed, which is deliberately source-agnostic. Time off blocks are not
  represented here, since they don't have a source calendar.

  `opts[:exclude_linked_to]` takes meetings (anything carrying `:uid` /
  `:provider_event_id`) whose own calendar events are left out — the public
  calendar passes the bookings awaiting approval, which it shows as their own
  chips, so their tentative hold isn't shown a second time as busy.
  """
  @spec busy_intervals_with_source(ProfileSchema.t(), DateTime.t(), DateTime.t(), keyword()) ::
          [{DateTime.t(), DateTime.t(), integer()}]
  def busy_intervals_with_source(
        %ProfileSchema{user_id: user_id} = profile,
        window_start,
        window_end,
        opts \\ []
      ) do
    timezone = profile.timezone || "Etc/UTC"

    user_id
    |> window_events(window_start, window_end, opts)
    |> Enum.filter(&CalendarEvent.blocking?/1)
    |> Enum.flat_map(fn event ->
      event
      |> event_interval(timezone)
      |> Enum.map(fn {start_at, end_at} ->
        {start_at, end_at, event.calendar_integration_id}
      end)
    end)
    |> clip_to_public_visibility(profile)
  end

  @doc """
  The timed events in the window that do *not* block availability because the
  calendar marks them as free (transparent) — typically an invitation the
  organiser has not answered yet. They are shown on the public calendar, as
  intervals tagged `:non_blocking` instead of a calendar id, so a visitor is
  told the time is taken up by something that does not stop them booking it.
  They never reach the free/busy feed or the availability calculation.

  All-day events, birthday/anniversary reminders and cancelled or declined
  events are left out, and the organiser's visible-hours window applies as it
  does to busy blocks. `opts[:exclude_linked_to]` works as in
  `busy_intervals_with_source/4`.
  """
  @spec non_blocking_intervals(ProfileSchema.t(), DateTime.t(), DateTime.t(), keyword()) ::
          [{DateTime.t(), DateTime.t(), :non_blocking}]
  def non_blocking_intervals(
        %ProfileSchema{user_id: user_id} = profile,
        window_start,
        window_end,
        opts \\ []
      ) do
    timezone = profile.timezone || "Etc/UTC"

    user_id
    |> window_events(window_start, window_end, opts)
    |> Enum.filter(&free_timed_event?/1)
    |> Enum.flat_map(fn event ->
      event
      |> event_interval(timezone)
      |> Enum.map(fn {start_at, end_at} -> {start_at, end_at, :non_blocking} end)
    end)
    |> clip_to_public_visibility(profile)
  end

  # Free (transparent) and still on: cancelled and declined events are not
  # shown as anything, and all-day ones (holidays, out-of-office markers)
  # would flood a day's cell.
  defp free_timed_event?(%CalendarEvent{} = event) do
    event.transparency == :transparent and event.status not in [:cancelled, :declined] and
      not event.all_day
  end

  # Every non-reminder event of the user's active calendars in the window,
  # whatever its transparency or status, minus the events of the meetings in
  # `opts[:exclude_linked_to]`.
  defp window_events(user_id, window_start, window_end, opts) do
    excluded = opts |> Keyword.get(:exclude_linked_to, []) |> Meetings.calendar_identifier_set()

    user_id
    |> CalendarIntegrationQueries.list_active_for_user()
    |> Enum.map(& &1.id)
    |> CalendarEventQueries.in_range({window_start, window_end})
    |> Enum.reject(
      &(CalendarEvent.reminder?(&1) or Meetings.linked_to_calendar_event?(&1, excluded))
    )
  end

  @doc """
  Restricts `{start, end, ...}` intervals to what the organiser publishes: their
  daily visible-hours window (`clip_to_visible_window/4`), then — unless
  `ProfileSchema.public_calendar_show_weekends` is on — weekdays only
  (`drop_weekends/3`), both in the profile's timezone.

  The one place both settings are applied, shared by the free/busy ICS feed
  and the public calendar page (`TymeslotWeb.Public.CalendarLive`, which also
  runs its pending-approval chips through it), so a visitor sees the same
  busy times everywhere.
  """
  @spec clip_to_public_visibility([tuple()], ProfileSchema.t()) :: [tuple()]
  def clip_to_public_visibility(intervals, %ProfileSchema{} = profile) do
    timezone = profile.timezone || "Etc/UTC"

    intervals
    |> clip_to_visible_window(
      timezone,
      profile.public_calendar_visible_from,
      profile.public_calendar_visible_to
    )
    |> drop_weekends(timezone, profile.public_calendar_show_weekends)
  end

  @doc """
  Removes the Saturday and Sunday parts (local days in `timezone`) of each
  `{start, end, ...}` interval, unless `show_weekends?` is true. An interval
  spanning a weekend keeps its weekday stretches, each consecutive run of
  weekdays as one piece; one lying wholly on a weekend is dropped.
  """
  @spec drop_weekends([tuple()], String.t(), boolean()) :: [tuple()]
  def drop_weekends(intervals, _timezone, true = _show_weekends?), do: intervals

  def drop_weekends(intervals, timezone, _show_weekends?) do
    Enum.flat_map(intervals, fn interval ->
      interval
      |> elem(0)
      |> weekday_pieces(elem(interval, 1), timezone)
      |> Enum.map(fn {piece_start, piece_end} ->
        interval |> put_elem(0, piece_start) |> put_elem(1, piece_end)
      end)
    end)
  end

  # Each local day the interval touches, clipped to that day and kept only on
  # weekdays; adjacent pieces (a Monday–Friday stretch) are merged back into
  # one, so an interval without a weekend day comes out unchanged.
  defp weekday_pieces(start_at, end_at, timezone) do
    local_start = DateTime.shift_zone!(start_at, timezone)
    local_end = DateTime.shift_zone!(end_at, timezone)

    local_start
    |> DateTime.to_date()
    |> Date.range(DateTime.to_date(local_end))
    |> Enum.reject(&(Date.day_of_week(&1) in [6, 7]))
    |> Enum.flat_map(fn day ->
      day_start = local_midnight_utc(day, timezone)
      day_end = local_midnight_utc(Date.add(day, 1), timezone)
      piece_start = Enum.max([start_at, day_start], DateTime)
      piece_end = Enum.min([end_at, day_end], DateTime)

      if DateTime.compare(piece_start, piece_end) == :lt,
        do: [{piece_start, piece_end}],
        else: []
    end)
    |> merge_adjacent()
  end

  # Total even where midnight falls in a DST gap.
  defp local_midnight_utc(day, timezone) do
    day
    |> DateTimeUtils.create_datetime_safe(~T[00:00:00], timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp merge_adjacent(pieces) do
    pieces
    |> Enum.reduce([], fn
      {piece_start, piece_end}, [{prev_start, prev_end} | rest] ->
        if DateTime.compare(prev_end, piece_start) == :eq,
          do: [{prev_start, piece_end} | rest],
          else: [{piece_start, piece_end}, {prev_start, prev_end} | rest]

      piece, [] ->
        [piece]
    end)
    |> Enum.reverse()
  end

  @doc """
  Clips each `{start, end, ...}` interval to the organiser's configured daily
  visible-hours window (`ProfileSchema.public_calendar_visible_from/to`),
  splitting a multi-day interval into one clipped piece per calendar day it
  touches (in `timezone`) and dropping any day with no overlap at all.
  Leaves `intervals` untouched when either bound is unset — the feature is
  off by default and only activates once both are configured (enforced by
  `ProfileSchema.changeset/2`).

  Applied everywhere a visitor can see an organiser's busy times through
  `clip_to_public_visibility/2`, together with the weekend setting.
  """
  @spec clip_to_visible_window([tuple()], String.t(), Time.t() | nil, Time.t() | nil) :: [
          tuple()
        ]
  def clip_to_visible_window(intervals, _timezone, nil, _visible_to), do: intervals
  def clip_to_visible_window(intervals, _timezone, _visible_from, nil), do: intervals

  def clip_to_visible_window(intervals, timezone, %Time{} = visible_from, %Time{} = visible_to) do
    Enum.flat_map(intervals, fn interval ->
      start_at = elem(interval, 0)
      end_at = elem(interval, 1)

      start_at
      |> daily_window_overlaps(end_at, timezone, visible_from, visible_to)
      |> Enum.map(fn {clipped_start, clipped_end} ->
        interval |> put_elem(0, clipped_start) |> put_elem(1, clipped_end)
      end)
    end)
  end

  # One entry per local calendar day the interval touches, each clamped to
  # that day's [visible_from, visible_to] window and converted back to UTC;
  # days with no overlap (the interval doesn't reach that day's window, or
  # the window doesn't reach the interval) are simply absent from the result.
  defp daily_window_overlaps(start_at, end_at, timezone, visible_from, visible_to) do
    local_start = DateTime.shift_zone!(start_at, timezone)
    local_end = DateTime.shift_zone!(end_at, timezone)

    DateTime.to_date(local_start)
    |> Date.range(DateTime.to_date(local_end))
    |> Enum.flat_map(fn day ->
      window_start =
        DateTime.shift_zone!(DateTime.new!(day, visible_from, timezone), "Etc/UTC")

      window_end = DateTime.shift_zone!(DateTime.new!(day, visible_to, timezone), "Etc/UTC")

      clipped_start = Enum.max([start_at, window_start], DateTime)
      clipped_end = Enum.min([end_at, window_end], DateTime)

      if DateTime.compare(clipped_start, clipped_end) == :lt do
        [{clipped_start, clipped_end}]
      else
        []
      end
    end)
  end

  # Timed events map directly; all-day events span midnight-to-midnight in the
  # profile's own timezone, not UTC — a birthday on the 18th blocks the whole
  # 18th for an organiser in Europe/Prague, not 02:00 on the 18th to 02:00 on
  # the 19th UTC.
  defp event_interval(
         %CalendarEvent{all_day: false, start_at: %DateTime{} = s, end_at: %DateTime{} = e},
         _timezone
       ),
       do: [{s, e}]

  defp event_interval(
         %CalendarEvent{all_day: true, start_date: %Date{} = sd, end_date: %Date{} = ed},
         timezone
       ) do
    [
      {DateTime.shift_zone!(DateTime.new!(sd, ~T[00:00:00], timezone), "Etc/UTC"),
       DateTime.shift_zone!(DateTime.new!(ed, ~T[00:00:00], timezone), "Etc/UTC")}
    ]
  end

  defp event_interval(_other, _timezone), do: []

  defp organizer_email(%ProfileSchema{user: %{email: email}})
       when is_binary(email) and email != "",
       do: email

  defp organizer_email(_profile), do: nil

  defp generate_token do
    @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end
end
