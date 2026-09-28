defmodule Tymeslot.CalendarGridEventsTest do
  @moduledoc """
  Covers `CalendarGrid`'s colour assignment, cached-event range queries, and
  manual refresh enqueueing. Split from `CalendarGridSyncTest` (staleness/
  sync-timestamp helpers) purely to keep both modules under the 650-line
  Credo limit — no functional relationship between the split beyond both
  covering `Tymeslot.CalendarGrid`.
  """

  use Tymeslot.DataCase, async: true

  @moduletag :calendar

  use Oban.Testing, repo: Tymeslot.Repo

  alias Tymeslot.CalendarGrid
  alias Tymeslot.Integrations.Calendar.EventColour
  alias Tymeslot.Workers.RefreshOutlookCalendarWorker
  alias Tymeslot.Workers.SyncCalDavCalendarWorker
  alias Tymeslot.Workers.SyncExchangeCalendarWorker
  alias Tymeslot.Workers.SyncGoogleCalendarWorker
  alias Tymeslot.Workers.SyncIcsCalendarWorker

  describe "integration_colour_classes/1" do
    test "returns empty map for empty list" do
      assert CalendarGrid.integration_colour_classes([]) == %{}
    end

    test "assigns the first rotation class to a single integration" do
      result = CalendarGrid.integration_colour_classes([%{id: 42, colour: nil}])
      assert result == %{42 => "bg-calendar-1"}
    end

    test "assigns rotation classes by sorted id, not input order" do
      integrations = [%{id: 30, colour: nil}, %{id: 10, colour: nil}, %{id: 20, colour: nil}]
      result = CalendarGrid.integration_colour_classes(integrations)

      assert result == %{
               10 => "bg-calendar-1",
               20 => "bg-calendar-2",
               30 => "bg-calendar-3"
             }
    end

    test "wraps the rotation once the classes run out" do
      integrations = Enum.map(1..10, &%{id: &1, colour: nil})
      result = CalendarGrid.integration_colour_classes(integrations)

      assert result[1] == "bg-calendar-1"
      assert result[8] == "bg-calendar-8"
      assert result[9] == "bg-calendar-1"
      assert result[10] == "bg-calendar-2"
    end

    test "a chosen colour wins over the rotation" do
      integrations = [%{id: 10, colour: nil}, %{id: 20, colour: "peacock"}]
      result = CalendarGrid.integration_colour_classes(integrations)

      assert result[20] == EventColour.tailwind_class("peacock")
      refute result[20] == "bg-calendar-2"
    end

    test "a chosen colour does not shift the rotation for the others" do
      unpicked = [%{id: 10, colour: nil}, %{id: 20, colour: nil}, %{id: 30, colour: nil}]
      picked = [%{id: 10, colour: nil}, %{id: 20, colour: "grape"}, %{id: 30, colour: nil}]

      assert CalendarGrid.integration_colour_classes(unpicked)[30] ==
               CalendarGrid.integration_colour_classes(picked)[30]
    end

    test "an unrecognised stored colour paints neutral rather than crashing" do
      result = CalendarGrid.integration_colour_classes([%{id: 10, colour: "burnt-sienna"}])
      assert result[10] == EventColour.fallback_class()
    end

    test "a blank stored colour falls back to the rotation" do
      result = CalendarGrid.integration_colour_classes([%{id: 10, colour: ""}])
      assert result[10] == "bg-calendar-1"
    end

    test "an integration map without the colour key still rotates" do
      result = CalendarGrid.integration_colour_classes([%{id: 10}])
      assert result[10] == "bg-calendar-1"
    end
  end

  describe "list_events_for_range/3" do
    setup do
      integration = insert(:calendar_integration)
      %{integration: integration}
    end

    test "returns events within the time range", %{integration: integration} do
      event =
        insert(:provider_calendar_event,
          calendar_integration: integration,
          start_at: ~U[2026-03-15 10:00:00Z],
          end_at: ~U[2026-03-15 11:00:00Z]
        )

      result =
        CalendarGrid.list_events_for_range(
          [integration.id],
          ~U[2026-03-15 00:00:00Z],
          ~U[2026-03-16 00:00:00Z]
        )

      assert [found] = result
      assert found.id == event.id
    end

    test "excludes events outside the time range", %{integration: integration} do
      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2026-03-10 10:00:00Z],
        end_at: ~U[2026-03-10 11:00:00Z]
      )

      result =
        CalendarGrid.list_events_for_range(
          [integration.id],
          ~U[2026-03-15 00:00:00Z],
          ~U[2026-03-16 00:00:00Z]
        )

      assert result == []
    end

    test "excludes events from other integrations", %{integration: integration} do
      other = insert(:calendar_integration)

      insert(:provider_calendar_event,
        calendar_integration: other,
        start_at: ~U[2026-03-15 10:00:00Z],
        end_at: ~U[2026-03-15 11:00:00Z]
      )

      result =
        CalendarGrid.list_events_for_range(
          [integration.id],
          ~U[2026-03-15 00:00:00Z],
          ~U[2026-03-16 00:00:00Z]
        )

      assert result == []
    end

    test "excludes events ending exactly at range start (strict boundary)", %{
      integration: integration
    } do
      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2026-03-14 23:00:00Z],
        end_at: ~U[2026-03-15 00:00:00Z]
      )

      result =
        CalendarGrid.list_events_for_range(
          [integration.id],
          ~U[2026-03-15 00:00:00Z],
          ~U[2026-03-16 00:00:00Z]
        )

      assert result == []
    end

    test "returns empty list when no events match", %{integration: integration} do
      result =
        CalendarGrid.list_events_for_range(
          [integration.id],
          ~U[2026-03-15 00:00:00Z],
          ~U[2026-03-16 00:00:00Z]
        )

      assert result == []
    end

    test "returns empty list for empty integration IDs" do
      result =
        CalendarGrid.list_events_for_range(
          [],
          ~U[2026-03-15 00:00:00Z],
          ~U[2026-03-16 00:00:00Z]
        )

      assert result == []
    end

    test "normalises string-keyed reminders round-tripped through JSONB", %{
      integration: integration
    } do
      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: ~U[2026-03-15 10:00:00Z],
        end_at: ~U[2026-03-15 11:00:00Z],
        reminders: [
          %{"method" => "popup", "minutes_before" => 30},
          %{"method" => "email", "minutes_before" => 1440}
        ]
      )

      assert [found] =
               CalendarGrid.list_events_for_range(
                 [integration.id],
                 ~U[2026-03-15 00:00:00Z],
                 ~U[2026-03-16 00:00:00Z]
               )

      assert found.reminders == [
               %{method: :popup, minutes_before: 30},
               %{method: :email, minutes_before: 1440}
             ]
    end
  end

  describe "refresh_events/1" do
    test "enqueues SyncGoogleCalendarWorker for google integrations" do
      integration = insert(:calendar_integration, provider: "google")

      {:ok, %{enqueued: 1, skipped: 0, errors: []}} =
        CalendarGrid.refresh_events(integration.user_id)

      assert_enqueued(
        worker: SyncGoogleCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end

    test "enqueues SyncCalDavCalendarWorker for caldav integrations" do
      integration = insert(:calendar_integration, provider: "caldav")

      {:ok, %{enqueued: 1, skipped: 0, errors: []}} =
        CalendarGrid.refresh_events(integration.user_id)

      assert_enqueued(
        worker: SyncCalDavCalendarWorker,
        args: %{"calendar_integration_id" => integration.id, "force_full_fetch" => true}
      )
    end

    test "enqueues SyncCalDavCalendarWorker for radicale integrations" do
      integration = insert(:calendar_integration, provider: "radicale")

      {:ok, %{enqueued: 1, skipped: 0, errors: []}} =
        CalendarGrid.refresh_events(integration.user_id)

      assert_enqueued(
        worker: SyncCalDavCalendarWorker,
        args: %{"calendar_integration_id" => integration.id, "force_full_fetch" => true}
      )
    end

    test "enqueues RefreshOutlookCalendarWorker for outlook integrations" do
      # Regression: Outlook manual refresh used to short-circuit with {:ok, nil}
      # because the legacy event-level worker required a graph_resource_id. The
      # "Refresh now" button silently did nothing for Outlook users when webhook
      # delivery was missing or delayed. Manual refresh must enqueue an actual
      # job that performs a delta sync (or bootstrap, if no delta link yet).
      integration = insert(:calendar_integration, provider: "outlook")

      {:ok, %{enqueued: 1, skipped: 0, errors: []}} =
        CalendarGrid.refresh_events(integration.user_id)

      assert_enqueued(
        worker: RefreshOutlookCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end

    test "enqueues SyncExchangeCalendarWorker for exchange integrations" do
      # Without an explicit clause the catch-all answers
      # `{:error, "unknown provider: exchange"}`, so "Refresh now" reports a
      # failure and nothing is fetched.
      integration = insert(:calendar_integration, provider: "exchange")

      {:ok, %{enqueued: 1, skipped: 0, errors: []}} =
        CalendarGrid.refresh_events(integration.user_id)

      assert_enqueued(
        worker: SyncExchangeCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end

    test "counts every provider as enqueued across a mixed set" do
      user = insert(:user)
      google = insert(:calendar_integration, user: user, provider: "google")
      caldav = insert(:calendar_integration, user: user, provider: "caldav")
      outlook = insert(:calendar_integration, user: user, provider: "outlook")

      {:ok, result} = CalendarGrid.refresh_events(user.id)

      assert result.enqueued == 3
      assert result.skipped == 0
      assert result.errors == []

      assert_enqueued(
        worker: SyncGoogleCalendarWorker,
        args: %{"calendar_integration_id" => google.id}
      )

      assert_enqueued(
        worker: SyncCalDavCalendarWorker,
        args: %{"calendar_integration_id" => caldav.id, "force_full_fetch" => true}
      )

      assert_enqueued(
        worker: RefreshOutlookCalendarWorker,
        args: %{"calendar_integration_id" => outlook.id}
      )
    end

    test "returns zeros when user has no active integrations" do
      user = insert(:user)

      assert {:ok, %{enqueued: 0, skipped: 0, errors: []}} =
               CalendarGrid.refresh_events(user.id)
    end

    test "enqueues CalDAV sync job with force_full_fetch: true" do
      user = insert(:user)

      integration =
        insert(:calendar_integration,
          user: user,
          provider: "caldav",
          is_active: true
        )

      assert {:ok, %{enqueued: 1}} = CalendarGrid.refresh_events(user.id)

      assert_enqueued(
        worker: Tymeslot.Workers.SyncCalDavCalendarWorker,
        args: %{
          "calendar_integration_id" => integration.id,
          "force_full_fetch" => true
        }
      )
    end

    test "enqueues Radicale sync job with force_full_fetch: true" do
      user = insert(:user)

      integration =
        insert(:calendar_integration,
          user: user,
          provider: "radicale",
          is_active: true
        )

      assert {:ok, %{enqueued: 1}} = CalendarGrid.refresh_events(user.id)

      assert_enqueued(
        worker: Tymeslot.Workers.SyncCalDavCalendarWorker,
        args: %{
          "calendar_integration_id" => integration.id,
          "force_full_fetch" => true
        }
      )
    end

    test "Google refresh does NOT include force_full_fetch flag" do
      user = insert(:user)

      integration =
        insert(:calendar_integration,
          user: user,
          provider: "google",
          is_active: true
        )

      assert {:ok, %{enqueued: 1}} = CalendarGrid.refresh_events(user.id)

      assert_enqueued(
        worker: Tymeslot.Workers.SyncGoogleCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )

      refute_enqueued(
        worker: Tymeslot.Workers.SyncGoogleCalendarWorker,
        args: %{"force_full_fetch" => true}
      )
    end

    test "enqueues SyncIcsCalendarWorker for ics_url integrations" do
      integration = insert(:calendar_integration, provider: "ics_url")

      {:ok, %{enqueued: 1, skipped: 0, errors: []}} =
        CalendarGrid.refresh_events(integration.user_id)

      assert_enqueued(
        worker: SyncIcsCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end
  end
end
