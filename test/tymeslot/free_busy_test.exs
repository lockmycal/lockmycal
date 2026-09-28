defmodule Tymeslot.FreeBusyTest do
  use Tymeslot.DataCase, async: true

  @moduletag :database

  import Tymeslot.Factory

  alias Tymeslot.FreeBusy

  describe "feed token lifecycle" do
    test "enable_feed generates a token and is idempotent" do
      profile = insert(:profile)
      refute FreeBusy.feed_enabled?(profile)

      assert {:ok, enabled} = FreeBusy.enable_feed(profile)
      assert FreeBusy.feed_enabled?(enabled)
      # 24 random bytes, url-safe base64 without padding.
      assert enabled.freebusy_token =~ ~r/\A[A-Za-z0-9_-]{32}\z/

      assert {:ok, again} = FreeBusy.enable_feed(enabled)
      assert again.freebusy_token == enabled.freebusy_token
    end

    test "regenerate_token replaces the token" do
      {:ok, enabled} = FreeBusy.enable_feed(insert(:profile))

      assert {:ok, rotated} = FreeBusy.regenerate_token(enabled)
      assert rotated.freebusy_token != enabled.freebusy_token
    end

    test "disable_feed clears the token" do
      {:ok, enabled} = FreeBusy.enable_feed(insert(:profile))

      assert {:ok, disabled} = FreeBusy.disable_feed(enabled)
      refute FreeBusy.feed_enabled?(disabled)
    end

    test "get_profile_by_token round-trips an enabled feed" do
      {:ok, enabled} = FreeBusy.enable_feed(insert(:profile))

      assert {:ok, found} = FreeBusy.get_profile_by_token(enabled.freebusy_token)
      assert found.id == enabled.id
    end

    test "get_profile_by_token rejects unknown tokens" do
      assert {:error, :not_found} = FreeBusy.get_profile_by_token("nope")
    end
  end

  describe "busy_intervals/3" do
    setup do
      profile = insert(:profile)
      integration = insert(:calendar_integration, user: profile.user)
      %{profile: profile, integration: integration}
    end

    test "publishes time off as busy alongside calendar events" do
      profile = insert(:profile, timezone: "Europe/Berlin")

      insert(:provider_calendar_event,
        calendar_integration: insert(:calendar_integration, user: profile.user),
        start_at: ~U[2030-06-01 09:00:00Z],
        end_at: ~U[2030-06-01 10:00:00Z],
        transparency: "opaque",
        status: "confirmed"
      )

      insert(:time_off_period,
        profile: profile,
        starts_on: ~D[2030-06-10],
        ends_on: ~D[2030-06-11]
      )

      intervals =
        FreeBusy.busy_intervals(profile, ~U[2030-05-01 00:00:00Z], ~U[2030-07-01 00:00:00Z])

      assert {~U[2030-06-09 22:00:00Z], ~U[2030-06-11 22:00:00Z]} in intervals

      assert Enum.any?(intervals, fn {s, _e} ->
               DateTime.truncate(s, :second) == ~U[2030-06-01 09:00:00Z]
             end)
    end

    test "includes blocking (opaque) events in the window", %{
      profile: profile,
      integration: integration
    } do
      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2030-06-01 09:00:00Z],
        end_at: ~U[2030-06-01 10:00:00Z],
        transparency: "opaque",
        status: "confirmed"
      )

      intervals =
        FreeBusy.busy_intervals(profile, ~U[2030-05-01 00:00:00Z], ~U[2030-07-01 00:00:00Z])

      assert Enum.any?(intervals, fn {s, e} ->
               DateTime.truncate(s, :second) == ~U[2030-06-01 09:00:00Z] and
                 DateTime.truncate(e, :second) == ~U[2030-06-01 10:00:00Z]
             end)
    end

    test "excludes transparent (free) events", %{profile: profile, integration: integration} do
      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2030-06-01 09:00:00Z],
        end_at: ~U[2030-06-01 10:00:00Z],
        transparency: "transparent",
        status: "confirmed"
      )

      assert [] =
               FreeBusy.busy_intervals(
                 profile,
                 ~U[2030-05-01 00:00:00Z],
                 ~U[2030-07-01 00:00:00Z]
               )
    end

    test "maps all-day events to midnight-to-midnight in the profile's own timezone", %{
      profile: profile,
      integration: integration
    } do
      # Factory profile is Europe/Tallinn (EEST, UTC+3 in June) — a full day
      # there is NOT midnight-to-midnight UTC, so the asserted bounds are
      # offset by 3 hours. Anchoring all-day events to UTC midnight instead
      # would block the wrong hours for every non-UTC organiser.
      insert(:provider_calendar_event,
        calendar_integration: integration,
        all_day: true,
        start_date: ~D[2030-06-01],
        end_date: ~D[2030-06-02],
        start_at: nil,
        end_at: nil,
        transparency: "opaque",
        status: "confirmed"
      )

      intervals =
        FreeBusy.busy_intervals(profile, ~U[2030-05-01 00:00:00Z], ~U[2030-07-01 00:00:00Z])

      assert [{s, e}] = intervals
      assert s == ~U[2030-05-31 21:00:00Z]
      assert e == ~U[2030-06-01 21:00:00Z]
    end
  end

  describe "non_blocking_intervals/3" do
    setup do
      profile = insert(:profile, timezone: "Etc/UTC")
      integration = insert(:calendar_integration, user: profile.user)
      %{profile: profile, integration: integration}
    end

    defp non_blocking(profile) do
      FreeBusy.non_blocking_intervals(
        profile,
        ~U[2030-05-01 00:00:00Z],
        ~U[2030-07-01 00:00:00Z]
      )
    end

    test "returns a timed transparent event, tagged instead of carrying a calendar id", %{
      profile: profile,
      integration: integration
    } do
      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2030-06-01 09:00:00Z],
        end_at: ~U[2030-06-01 10:00:00Z],
        transparency: "transparent",
        status: "confirmed"
      )

      assert [{start_at, end_at, :non_blocking}] = non_blocking(profile)
      assert DateTime.truncate(start_at, :second) == ~U[2030-06-01 09:00:00Z]
      assert DateTime.truncate(end_at, :second) == ~U[2030-06-01 10:00:00Z]
    end

    test "leaves out opaque, all-day, cancelled and declined events and reminders", %{
      profile: profile,
      integration: integration
    } do
      base = [
        calendar_integration: integration,
        start_at: ~U[2030-06-01 09:00:00Z],
        end_at: ~U[2030-06-01 10:00:00Z],
        transparency: "transparent",
        status: "confirmed"
      ]

      insert(:provider_calendar_event, Keyword.merge(base, transparency: "opaque"))

      insert(
        :provider_calendar_event,
        Keyword.merge(base,
          all_day: true,
          start_at: nil,
          end_at: nil,
          start_date: ~D[2030-06-01],
          end_date: ~D[2030-06-02]
        )
      )

      insert(:provider_calendar_event, Keyword.merge(base, status: "cancelled"))
      insert(:provider_calendar_event, Keyword.merge(base, status: "declined"))
      insert(:provider_calendar_event, Keyword.merge(base, summary: "Klára – narozeniny"))

      assert [] = non_blocking(profile)
    end

    test "does not change the busy intervals", %{profile: profile, integration: integration} do
      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2030-06-01 09:00:00Z],
        end_at: ~U[2030-06-01 10:00:00Z],
        transparency: "transparent",
        status: "confirmed"
      )

      assert [] =
               FreeBusy.busy_intervals(
                 profile,
                 ~U[2030-05-01 00:00:00Z],
                 ~U[2030-07-01 00:00:00Z]
               )
    end
  end

  describe "feed/2" do
    test "renders a VFREEBUSY document with correct interval bounds and ORGANIZER" do
      profile = insert(:profile)
      integration = insert(:calendar_integration, user: profile.user)

      now = DateTime.utc_now()
      busy_start = DateTime.truncate(DateTime.add(now, 2, :day), :second)
      busy_end = DateTime.add(busy_start, 3600, :second)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: busy_start,
        end_at: busy_end,
        transparency: "opaque",
        status: "confirmed"
      )

      ics = FreeBusy.feed(profile, now: now)

      start_str = busy_start |> DateTime.to_iso8601(:basic) |> String.replace(~r/\.\d+/, "")
      end_str = busy_end |> DateTime.to_iso8601(:basic) |> String.replace(~r/\.\d+/, "")

      assert ics =~ "BEGIN:VFREEBUSY"
      assert ics =~ "FREEBUSY;FBTYPE=BUSY:#{start_str}/#{end_str}"
      assert ics =~ "ORGANIZER:mailto:#{profile.user.email}"
    end
  end

  describe "clip_to_visible_window/4" do
    test "passes intervals through unchanged when either bound is nil" do
      intervals = [{~U[2030-06-01 20:00:00Z], ~U[2030-06-01 22:00:00Z], 1}]

      assert FreeBusy.clip_to_visible_window(intervals, "Etc/UTC", nil, ~T[18:00:00]) ==
               intervals

      assert FreeBusy.clip_to_visible_window(intervals, "Etc/UTC", ~T[07:00:00], nil) ==
               intervals
    end

    test "clips an interval that partially overlaps a single day's window" do
      intervals = [{~U[2030-06-01 17:00:00Z], ~U[2030-06-01 19:00:00Z], 1}]

      assert FreeBusy.clip_to_visible_window(
               intervals,
               "Etc/UTC",
               ~T[07:00:00],
               ~T[18:00:00]
             ) == [{~U[2030-06-01 17:00:00Z], ~U[2030-06-01 18:00:00Z], 1}]
    end

    test "drops an interval that falls entirely outside the window" do
      intervals = [{~U[2030-06-01 20:00:00Z], ~U[2030-06-01 22:00:00Z], 1}]

      assert FreeBusy.clip_to_visible_window(
               intervals,
               "Etc/UTC",
               ~T[07:00:00],
               ~T[18:00:00]
             ) == []
    end

    test "splits a multi-day interval into one clipped piece per touched day" do
      # Monday 20:00 -> Wednesday 09:00. Monday's window (07:00-18:00) never
      # reaches 20:00, so Monday contributes nothing; Tuesday is covered
      # entirely by the interval, so its whole window shows; Wednesday is
      # clipped to where the interval ends.
      intervals = [{~U[2030-06-03 20:00:00Z], ~U[2030-06-05 09:00:00Z], 1}]

      assert FreeBusy.clip_to_visible_window(
               intervals,
               "Etc/UTC",
               ~T[07:00:00],
               ~T[18:00:00]
             ) == [
               {~U[2030-06-04 07:00:00Z], ~U[2030-06-04 18:00:00Z], 1},
               {~U[2030-06-05 07:00:00Z], ~U[2030-06-05 09:00:00Z], 1}
             ]
    end
  end

  describe "busy_intervals_with_source/3 with a visible-hours window" do
    test "clips busy blocks to the profile's configured window" do
      profile =
        insert(:profile,
          timezone: "Etc/UTC",
          public_calendar_visible_from: ~T[07:00:00],
          public_calendar_visible_to: ~T[18:00:00]
        )

      integration = insert(:calendar_integration, user: profile.user)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2030-06-01 17:00:00Z],
        end_at: ~U[2030-06-01 19:00:00Z],
        transparency: "opaque",
        status: "confirmed"
      )

      intervals =
        FreeBusy.busy_intervals_with_source(
          profile,
          ~U[2030-05-01 00:00:00Z],
          ~U[2030-07-01 00:00:00Z]
        )

      assert [{s, e, _integration_id}] = intervals
      assert DateTime.truncate(s, :second) == ~U[2030-06-01 17:00:00Z]
      assert DateTime.truncate(e, :second) == ~U[2030-06-01 18:00:00Z]
    end

    test "leaves busy blocks untouched when no window is configured" do
      profile = insert(:profile, timezone: "Etc/UTC")
      integration = insert(:calendar_integration, user: profile.user)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2030-06-01 17:00:00Z],
        end_at: ~U[2030-06-01 19:00:00Z],
        transparency: "opaque",
        status: "confirmed"
      )

      intervals =
        FreeBusy.busy_intervals_with_source(
          profile,
          ~U[2030-05-01 00:00:00Z],
          ~U[2030-07-01 00:00:00Z]
        )

      assert [{s, e, _integration_id}] = intervals
      assert DateTime.truncate(s, :second) == ~U[2030-06-01 17:00:00Z]
      assert DateTime.truncate(e, :second) == ~U[2030-06-01 19:00:00Z]
    end
  end
end
