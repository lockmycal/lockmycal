defmodule TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.RecurrenceRule do
  @moduledoc """
  Turns the recurrence editor's form fields into the RRULE an event is written
  with, and picks the timezone a series' UNTIL date ends its day in.
  """

  alias Tymeslot.Clock
  alias Tymeslot.Integrations.Calendar.Recurrence.RRule
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared

  @weekday_atoms %{
    "mo" => :mo,
    "tu" => :tu,
    "we" => :we,
    "th" => :th,
    "fr" => :fr,
    "sa" => :sa,
    "su" => :su
  }

  @doc """
  The timezone a recurring event's UNTIL date ends its day in: the event's own,
  falling back to the organiser's profile zone for an event that carries none.

  A series belongs to the calendar it sits on, not to whoever is looking at it,
  so reading the organiser's zone for both is only right while they agree. An
  organiser in `Europe/Tallinn` ending an `America/Los_Angeles` series on 31
  December otherwise gets an UNTIL at 13:59 Los Angeles time, cutting that day's
  afternoon occurrences; west-to-east the mirror case adds one.

  Creates pass the organiser's zone directly and do not call this: an event
  being drawn on the grid has no zone of its own yet, and the grid's wall clock
  is the organiser's.
  """
  @spec recurrence_timezone(map() | nil, String.t() | nil) :: String.t() | nil
  def recurrence_timezone(event, user_timezone)
  def recurrence_timezone(nil, user_timezone), do: user_timezone

  def recurrence_timezone(event, user_timezone) do
    case Map.get(event, :timezone) do
      zone when is_binary(zone) and zone != "" -> zone
      _none -> user_timezone
    end
  end

  @doc """
  Composes a canonical RRULE string from the recurrence editor's raw form
  fields (`freq`, `interval`, `by_day[]`, `end_type`, `count`, `until`).

  Returns `nil` when no frequency is chosen ("Does not repeat") or the fields do
  not describe a valid rule. Unrecognised frequencies and malformed end
  conditions degrade gracefully — a bad `count` simply yields a never-ending
  rule rather than failing.

  The optional `event_context` map may include:
    - `:start_date` — a `Date.t()` used to reject an `until` that precedes the
      event start (which would produce a dead rule with zero occurrences).
    - `:all_day` — a boolean that controls UNTIL value-type: all-day recurring
      events must emit `UNTIL=YYYYMMDD` (RFC 5545 §3.3.10) rather than the
      default UTC date-time form.
    - `:timezone` — the timezone whose day the UNTIL date ends, from
      `recurrence_timezone/2`. A timed event's UNTIL is an instant, so the date
      the form supplies has to end its day in a zone rather than in UTC, or the
      series ends a day early west of UTC and a day late east of it.
    - `:reference_date` — the date a default end date counts from, when
      `:start_date` isn't given (a new event, whose start can still change).

  Picking "After" or "On date" sends no `count` / `until` yet: the field for it
  only appears once the rule has one. That first change therefore gets a
  default — `default_recurrence_count/0` occurrences, or an end a month after
  the event's start — so the choice sticks and its field shows up. A value the
  organiser typed that doesn't parse still yields a never-ending rule.

  Returns `{:error, :until_before_start}` when `until` precedes `:start_date`.
  """
  @spec compose_recurrence_rule(map(), map()) :: String.t() | nil | {:error, :until_before_start}
  def compose_recurrence_rule(params, event_context \\ %{}) do
    case parse_freq(params["freq"]) do
      nil ->
        nil

      freq ->
        opts =
          %{freq: freq}
          |> put_interval(params["interval"])
          |> put_by_day(freq, params["by_day"])
          |> put_end_condition(params["end_type"], params, event_context)

        # `build/2` and `retarget/2` are handed the same value-type options, so
        # the rule composed here and the rule read back agree on how UNTIL is
        # written; retarget/2 is what rejects a series ending before it starts.
        fit_opts = [
          all_day: Map.get(event_context, :all_day, false),
          timezone: Map.get(event_context, :timezone),
          start_date: Map.get(event_context, :start_date)
        ]

        case RRule.retarget(RRule.build(opts, fit_opts), fit_opts) do
          {:ok, rule} -> rule
          {:error, :until_before_start} = error -> error
        end
    end
  end

  defp parse_freq("daily"), do: :daily
  defp parse_freq("weekly"), do: :weekly
  defp parse_freq("monthly"), do: :monthly
  defp parse_freq("yearly"), do: :yearly
  defp parse_freq(_other), do: nil

  defp put_interval(opts, value) do
    case Shared.parse_int(value || "") do
      {:ok, n} when n > 1 -> Map.put(opts, :interval, n)
      _other -> opts
    end
  end

  defp put_by_day(opts, :weekly, days) when is_list(days) do
    by_day =
      days
      |> Enum.map(&Map.get(@weekday_atoms, &1))
      |> Enum.reject(&is_nil/1)

    if by_day == [], do: opts, else: Map.put(opts, :by_day, by_day)
  end

  defp put_by_day(opts, _freq, _days), do: opts

  @default_recurrence_count 10

  @doc "How many occurrences a series ending “after N” starts with."
  @spec default_recurrence_count() :: pos_integer()
  def default_recurrence_count, do: @default_recurrence_count

  defp put_end_condition(opts, "count", params, _event_context)
       when not is_map_key(params, "count"),
       do: Map.put(opts, :count, @default_recurrence_count)

  defp put_end_condition(opts, "count", params, _event_context) do
    case Shared.parse_int(params["count"] || "") do
      {:ok, n} when n > 0 -> Map.put(opts, :count, n)
      _other -> opts
    end
  end

  defp put_end_condition(opts, "until", params, event_context)
       when not is_map_key(params, "until"),
       do: Map.put(opts, :until, default_until(event_context))

  defp put_end_condition(opts, "until", params, _event_context) do
    case Date.from_iso8601(params["until"] || "") do
      {:ok, date} -> Map.put(opts, :until, date)
      {:error, _reason} -> opts
    end
  end

  defp put_end_condition(opts, _never_or_other, _params, _event_context), do: opts

  defp default_until(event_context) do
    from =
      Map.get(event_context, :start_date) || Map.get(event_context, :reference_date) ||
        Clock.utc_today()

    Date.shift(from, month: 1)
  end
end
