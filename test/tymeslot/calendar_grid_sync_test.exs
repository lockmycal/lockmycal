defmodule Tymeslot.CalendarGridSyncTest do
  @moduledoc """
  Covers `CalendarGrid`'s staleness detection and sync-timestamp helpers.
  Split from `CalendarGridEventsTest` (colours/range queries/refresh
  enqueueing) purely to keep both modules under the 650-line Credo limit —
  no functional relationship between the split beyond both covering
  `Tymeslot.CalendarGrid`.
  """

  use Tymeslot.DataCase, async: true

  @moduletag :calendar

  alias Tymeslot.CalendarGrid

  describe "stale_integrations/1" do
    test "returns integrations with nil last_external_sync_at" do
      integration = %{
        id: 1,
        provider: "google",
        caldav_sync_tier: nil,
        last_external_sync_at: nil
      }

      assert [^integration] = CalendarGrid.stale_integrations([integration])
    end

    test "returns webhook provider stale after 30 minutes" do
      stale_time = DateTime.add(DateTime.utc_now(), -31, :minute)

      integration = %{
        id: 1,
        provider: "google",
        caldav_sync_tier: nil,
        last_external_sync_at: stale_time
      }

      assert [^integration] = CalendarGrid.stale_integrations([integration])
    end

    test "excludes webhook provider synced within 30 minutes" do
      recent_time = DateTime.add(DateTime.utc_now(), -10, :minute)

      integration = %{
        id: 1,
        provider: "google",
        caldav_sync_tier: nil,
        last_external_sync_at: recent_time
      }

      assert [] = CalendarGrid.stale_integrations([integration])
    end

    test "uses tier-aware thresholds for CalDAV providers" do
      # Tier 1 (sync-token): 25 min threshold
      fresh_t1 = %{
        id: 1,
        provider: "caldav",
        caldav_sync_tier: 1,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -20, :minute)
      }

      assert [] = CalendarGrid.stale_integrations([fresh_t1])

      stale_t1 = %{
        id: 2,
        provider: "caldav",
        caldav_sync_tier: 1,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -30, :minute)
      }

      assert [^stale_t1] = CalendarGrid.stale_integrations([stale_t1])

      # Tier 2 (CTag): 45 min threshold
      fresh_t2 = %{
        id: 3,
        provider: "caldav",
        caldav_sync_tier: 2,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -40, :minute)
      }

      assert [] = CalendarGrid.stale_integrations([fresh_t2])

      stale_t2 = %{
        id: 4,
        provider: "caldav",
        caldav_sync_tier: 2,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -50, :minute)
      }

      assert [^stale_t2] = CalendarGrid.stale_integrations([stale_t2])

      # Tier 3 (full fetch): 90 min threshold
      fresh_t3 = %{
        id: 5,
        provider: "caldav",
        caldav_sync_tier: 3,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -80, :minute)
      }

      assert [] = CalendarGrid.stale_integrations([fresh_t3])

      stale_t3 = %{
        id: 6,
        provider: "caldav",
        caldav_sync_tier: 3,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -100, :minute)
      }

      assert [^stale_t3] = CalendarGrid.stale_integrations([stale_t3])
    end

    test "uses default threshold for CalDAV with nil tier" do
      # nil tier uses 25 min default (same as Tier 1)
      fresh = %{
        id: 1,
        provider: "caldav",
        caldav_sync_tier: nil,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -20, :minute)
      }

      assert [] = CalendarGrid.stale_integrations([fresh])

      stale = %{
        id: 2,
        provider: "caldav",
        caldav_sync_tier: nil,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -30, :minute)
      }

      assert [^stale] = CalendarGrid.stale_integrations([stale])
    end

    test "uses 75-minute threshold for ics_url subscriptions" do
      fresh = %{
        id: 1,
        provider: "ics_url",
        caldav_sync_tier: nil,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -60, :minute)
      }

      assert [] = CalendarGrid.stale_integrations([fresh])

      stale = %{
        id: 2,
        provider: "ics_url",
        caldav_sync_tier: nil,
        last_external_sync_at: DateTime.add(DateTime.utc_now(), -80, :minute)
      }

      assert [^stale] = CalendarGrid.stale_integrations([stale])
    end

    test "applies CalDAV thresholds to all CalDAV-based providers" do
      recent = DateTime.add(DateTime.utc_now(), -10, :minute)

      for provider <- ~w(caldav radicale nextcloud zimbra) do
        integration = %{
          id: 1,
          provider: provider,
          caldav_sync_tier: 1,
          last_external_sync_at: recent
        }

        assert [] = CalendarGrid.stale_integrations([integration])
      end
    end

    test "returns empty list when all integrations are fresh" do
      recent = DateTime.add(DateTime.utc_now(), -5, :minute)

      integrations = [
        %{id: 1, provider: "google", caldav_sync_tier: nil, last_external_sync_at: recent},
        %{id: 2, provider: "outlook", caldav_sync_tier: nil, last_external_sync_at: recent}
      ]

      assert [] = CalendarGrid.stale_integrations(integrations)
    end

    test "excludes Outlook pending initial setup from stale" do
      # Outlook with no delta link and no sync: pending setup, not stale
      pending = %{
        id: 1,
        provider: "outlook",
        caldav_sync_tier: nil,
        graph_delta_link: nil,
        last_external_sync_at: nil
      }

      assert [] = CalendarGrid.stale_integrations([pending])
    end

    test "includes Outlook with delta link but nil sync as stale" do
      # Has a delta link but no sync timestamp: something is wrong
      broken = %{
        id: 1,
        provider: "outlook",
        caldav_sync_tier: nil,
        graph_delta_link: "https://graph.microsoft.com/v1.0/me/calendarView/delta?token=abc",
        last_external_sync_at: nil
      }

      assert [^broken] = CalendarGrid.stale_integrations([broken])
    end

    test "filters mixed fresh and stale integrations" do
      recent = DateTime.add(DateTime.utc_now(), -5, :minute)
      stale_time = DateTime.add(DateTime.utc_now(), -60, :minute)

      fresh = %{id: 1, provider: "google", caldav_sync_tier: nil, last_external_sync_at: recent}

      stale = %{
        id: 2,
        provider: "outlook",
        caldav_sync_tier: nil,
        last_external_sync_at: stale_time
      }

      assert [^stale] = CalendarGrid.stale_integrations([fresh, stale])
    end
  end

  describe "oldest_sync_at/1" do
    test "returns nil for empty list" do
      assert CalendarGrid.oldest_sync_at([]) == nil
    end

    test "returns nil when all integrations have nil sync times" do
      integrations = [
        %{last_external_sync_at: nil},
        %{last_external_sync_at: nil}
      ]

      assert CalendarGrid.oldest_sync_at(integrations) == nil
    end

    test "returns the earliest timestamp" do
      old = ~U[2026-03-18 08:00:00Z]
      recent = ~U[2026-03-18 12:00:00Z]

      integrations = [
        %{last_external_sync_at: recent},
        %{last_external_sync_at: old}
      ]

      assert CalendarGrid.oldest_sync_at(integrations) == old
    end

    test "ignores nil values and returns earliest non-nil" do
      timestamp = ~U[2026-03-18 10:00:00Z]

      integrations = [
        %{last_external_sync_at: nil},
        %{last_external_sync_at: timestamp}
      ]

      assert CalendarGrid.oldest_sync_at(integrations) == timestamp
    end
  end

  describe "most_recent_sync_at/1" do
    test "returns nil for empty list" do
      assert CalendarGrid.most_recent_sync_at([]) == nil
    end

    test "returns nil when all integrations have nil sync times" do
      integrations = [
        %{last_external_sync_at: nil},
        %{last_external_sync_at: nil}
      ]

      assert CalendarGrid.most_recent_sync_at(integrations) == nil
    end

    test "returns the latest timestamp" do
      old = ~U[2026-03-18 08:00:00Z]
      recent = ~U[2026-03-18 12:00:00Z]

      integrations = [
        %{last_external_sync_at: old},
        %{last_external_sync_at: recent}
      ]

      assert CalendarGrid.most_recent_sync_at(integrations) == recent
    end

    test "ignores nil values and returns latest non-nil" do
      timestamp = ~U[2026-03-18 10:00:00Z]

      integrations = [
        %{last_external_sync_at: nil},
        %{last_external_sync_at: timestamp}
      ]

      assert CalendarGrid.most_recent_sync_at(integrations) == timestamp
    end
  end
end
