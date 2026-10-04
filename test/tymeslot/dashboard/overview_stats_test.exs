defmodule Tymeslot.Dashboard.OverviewStatsTest do
  # Not async: toggles the global `:booking_analytics_enabled` app env.
  use Tymeslot.DataCase, async: false

  @moduletag :dashboard

  alias Tymeslot.Dashboard.OverviewStats
  alias Tymeslot.Infrastructure.DashboardCache

  # Wednesday noon, so the Monday–Sunday week has room on both sides.
  @now ~U[2026-09-30 12:00:00Z]

  setup do
    user = insert(:user)

    on_exit(fn ->
      DashboardCache.invalidate(DashboardCache.integration_attention_key(user.id))
    end)

    {:ok, user: user}
  end

  defp meeting_at(user, start_time, attrs \\ []) do
    insert(
      :meeting,
      [
        organizer_user_id: user.id,
        organizer_email: user.email,
        start_time: start_time,
        end_time: DateTime.add(start_time, 3600, :second)
      ] ++ attrs
    )
  end

  describe "week_bookings" do
    test "counts live bookings starting Monday to Sunday in the organizer's zone", %{user: user} do
      meeting_at(user, ~U[2026-09-28 08:00:00Z])
      meeting_at(user, ~U[2026-10-04 20:00:00Z])
      # Outside the week on either side.
      meeting_at(user, ~U[2026-09-27 20:00:00Z])
      meeting_at(user, ~U[2026-10-05 08:00:00Z])
      # Inside the week but not holding a slot.
      meeting_at(user, ~U[2026-09-30 15:00:00Z], status: "cancelled")
      # Another organizer's booking.
      meeting_at(insert(:user), ~U[2026-09-30 15:00:00Z])

      assert %OverviewStats{week_bookings: 2} = OverviewStats.build(user, "Etc/UTC", now: @now)
    end

    test "uses the organizer's local week boundaries", %{user: user} do
      # Sunday 23:30 UTC is already Monday 01:30 in Prague (UTC+2 in September).
      meeting_at(user, ~U[2026-09-27 23:30:00Z])

      assert %OverviewStats{week_bookings: 0} = OverviewStats.build(user, "Etc/UTC", now: @now)

      assert %OverviewStats{week_bookings: 1} =
               OverviewStats.build(user, "Europe/Prague", now: @now)
    end
  end

  test "counts bookings awaiting approval and open polls", %{user: user} do
    meeting_at(user, ~U[2026-10-10 09:00:00Z], status: "awaiting_approval")
    insert(:poll, user: user)
    insert(:poll, user: user, status: :cancelled)

    assert %OverviewStats{awaiting_approval: 1, open_polls: 1} =
             OverviewStats.build(user, "Etc/UTC", now: @now)
  end

  test "counts active integrations needing reauth, but not paused ones", %{user: user} do
    insert(:calendar_integration, user: user, needs_reauth: true)
    insert(:calendar_integration, user: user, needs_reauth: true, is_active: false)
    insert(:calendar_integration, user: user)
    insert(:video_integration, user: user, needs_reauth: true)

    assert %OverviewStats{calendar_attention: 1, video_attention: 1} =
             OverviewStats.build(user, "Etc/UTC", now: @now)
  end

  describe "analytics" do
    setup do
      previous = Application.fetch_env(:tymeslot, :booking_analytics_enabled)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:tymeslot, :booking_analytics_enabled, value)
          :error -> Application.delete_env(:tymeslot, :booking_analytics_enabled)
        end
      end)
    end

    test "stays nil unless the user is allowed and collection is enabled", %{user: user} do
      Application.put_env(:tymeslot, :booking_analytics_enabled, true)
      assert %OverviewStats{analytics: nil} = OverviewStats.build(user, "Etc/UTC", now: @now)

      Application.put_env(:tymeslot, :booking_analytics_enabled, false)

      assert %OverviewStats{analytics: nil} =
               OverviewStats.build(user, "Etc/UTC", now: @now, analytics_allowed: true)
    end

    test "summarises the last 7 days when allowed and enabled", %{user: user} do
      Application.put_env(:tymeslot, :booking_analytics_enabled, true)

      assert %OverviewStats{analytics: analytics} =
               OverviewStats.build(user, "Etc/UTC", now: @now, analytics_allowed: true)

      assert %{visits: 0, bookings: 0, conversion_rate: "0.0", to: @now} = analytics
      assert DateTime.diff(analytics.to, analytics.from, :day) == 7
    end
  end
end
