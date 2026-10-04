defmodule Tymeslot.Dashboard.OverviewStats do
  @moduledoc """
  The figures behind the dashboard Overview's KPI tiles and side widgets:
  bookings this week, bookings awaiting approval, open polls, integrations that
  need attention and — when the organizer may see analytics — a 7-day traffic
  summary.

  Built on the same 60-second cadence as the Overview's agenda (see
  `DashboardContext.get_dashboard_data_for_action/4`); each figure is a single
  aggregate query, and the analytics bundle is shared with the Analytics page
  through `Analytics.cached_metrics/5`.
  """

  alias Tymeslot.Analytics
  alias Tymeslot.Infrastructure.DashboardCache
  alias Tymeslot.Integrations.CalendarManagement
  alias Tymeslot.Integrations.HealthCheck
  alias Tymeslot.Integrations.HealthCheck.Monitor
  alias Tymeslot.Integrations.Video
  alias Tymeslot.Meetings
  alias Tymeslot.Polls
  alias Tymeslot.Utils.DateTimeUtils

  @analytics_range "7d"
  @analytics_days 7

  @type analytics :: %{
          visits: non_neg_integer(),
          unique_visitors: non_neg_integer(),
          bookings: non_neg_integer(),
          conversion_rate: String.t(),
          visits_by_day: [map()],
          from: DateTime.t(),
          to: DateTime.t()
        }

  @type t :: %__MODULE__{
          week_bookings: non_neg_integer(),
          awaiting_approval: non_neg_integer(),
          open_polls: non_neg_integer(),
          calendar_attention: non_neg_integer(),
          video_attention: non_neg_integer(),
          analytics: analytics() | nil
        }

  defstruct week_bookings: 0,
            awaiting_approval: 0,
            open_polls: 0,
            calendar_attention: 0,
            video_attention: 0,
            analytics: nil

  @doc """
  Builds the Overview figures for `user` in `timezone`.

  Options:
    * `:analytics_allowed` — the organizer's analytics entitlement. The 7-day
      summary is only computed when this is `true` *and* analytics collection
      is enabled for the installation; otherwise `analytics` stays `nil` and
      no analytics query runs.
    * `:now` — the reference instant (defaults to `DateTime.utc_now/0`).
  """
  @spec build(map(), String.t() | nil, keyword()) :: t()
  def build(%{id: user_id}, timezone, opts \\ []) when is_integer(user_id) do
    tz = timezone || "Etc/UTC"
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    {week_start, week_end} = week_bounds(now, tz)
    {calendar_attention, video_attention} = attention_counts(user_id)

    %__MODULE__{
      week_bookings: Meetings.count_live_bookings_starting(user_id, week_start, week_end),
      awaiting_approval: Meetings.count_awaiting_approval_for_organizer(user_id),
      open_polls: Polls.count_open_polls(user_id),
      calendar_attention: calendar_attention,
      video_attention: video_attention,
      analytics:
        if(Keyword.get(opts, :analytics_allowed, false) and Analytics.enabled?(),
          do: analytics(user_id, now, tz)
        )
    }
  end

  # Monday 00:00 to the following Monday 00:00, in the organizer's zone.
  defp week_bounds(now, tz) do
    monday =
      now
      |> DateTimeUtils.convert_to_timezone(tz)
      |> DateTime.to_date()
      |> Date.beginning_of_week(:monday)

    {DateTimeUtils.create_datetime_safe(monday, ~T[00:00:00], tz),
     DateTimeUtils.create_datetime_safe(Date.add(monday, 7), ~T[00:00:00], tz)}
  end

  # Same classification the Calendars and Video pages badge their rows with
  # (`HealthCheck.attention_status/2`); a paused integration is the user's own
  # choice, not something needing attention. Listing integrations decrypts
  # their credentials, so the result is cached rather than recomputed on every
  # agenda tick; `DashboardContext.invalidate_integration_status/1` drops it
  # whenever an integration changes.
  defp attention_counts(user_id) do
    case DashboardCache.get_or_compute(
           DashboardCache.integration_attention_key(user_id),
           fn -> compute_attention_counts(user_id) end,
           :timer.minutes(5)
         ) do
      {:error, _reason} -> {0, 0}
      counts -> counts
    end
  end

  defp compute_attention_counts(user_id) do
    health =
      user_id
      |> HealthCheck.list_unhealthy_for_user()
      |> Map.new(&{{&1.integration_type, &1.integration_id}, Monitor.from_db_record(&1)})

    {count_attention(CalendarManagement.list_calendar_integrations(user_id), "calendar", health),
     count_attention(Video.list_integrations(user_id), "video", health)}
  end

  defp count_attention(integrations, type, health) do
    Enum.count(integrations, fn integration ->
      HealthCheck.attention_status(integration, Map.get(health, {type, integration.id})) in [
        :needs_reauth,
        :unhealthy
      ]
    end)
  end

  # Same window the Analytics page uses for its "7d" range, so both read one
  # cached bundle.
  defp analytics(user_id, now, tz) do
    from = DateTime.add(now, -@analytics_days * 86_400, :second)
    metrics = Analytics.cached_metrics(user_id, @analytics_range, from, now, tz)

    %{
      visits: metrics.visits,
      unique_visitors: metrics.unique_visitors,
      bookings: metrics.bookings,
      conversion_rate:
        Analytics.conversion_rate(metrics.converting_visitors, metrics.unique_visitors),
      visits_by_day: metrics.visits_by_day,
      from: from,
      to: now
    }
  end
end
