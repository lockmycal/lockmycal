defmodule Tymeslot.Integrations.Calendar.CalDAV.OfflineQueueMoreTest do
  @moduledoc """
  Covers the offline write queue that replays locally-modified cache
  rows against the remote CalDAV server at the start of every sync
  cycle.
  """

  use Tymeslot.DataCase, async: false

  import Tymeslot.ConfigTestHelpers

  @moduletag :integrations
  @moduletag :unit

  alias Ecto.Adapters.SQL
  alias Plug.Conn
  alias Req.Test, as: ReqTest
  alias Tymeslot.Integrations.Calendar.CalDAV.OfflineQueue
  alias Tymeslot.Integrations.Calendar.CalDAV.QueueQueries
  alias Tymeslot.Integrations.Calendar.ProviderCalendarEventSchema
  alias Tymeslot.Repo

  @client %{
    base_url: "https://caldav.example.com",
    username: "user",
    password: "pass",
    calendar_paths: ["/cal/"],
    verify_ssl: true,
    provider: :caldav
  }

  defp insert_pending_row(integration, attrs) do
    defaults = %{
      calendar_integration: integration,
      uid: "queue-event-uid",
      provider: "caldav",
      provider_calendar_id: "/cal/",
      provider_event_id: "/cal/queue-event-uid.ics",
      summary: "Queued",
      start_at: ~U[2026-04-15 14:00:00.000000Z],
      end_at: ~U[2026-04-15 15:00:00.000000Z],
      all_day: false,
      timezone: "UTC",
      synced_at: ~U[2026-04-15 00:00:00.000000Z],
      etag: "\"cached-etag\""
    }

    insert(:provider_calendar_event, Map.merge(defaults, Map.new(attrs)))
  end

  setup do
    with_config(:tymeslot, :http_client_module, Tymeslot.Infrastructure.HTTPClient)

    integration =
      insert(:calendar_integration,
        provider: "caldav",
        calendar_paths: ["/cal/"]
      )

    {:ok, integration: integration}
  end

  describe "flush/2 — multi-calendar connections" do
    test "replays a row against the calendar it was tagged for, not the connection's first path",
         %{integration: integration} do
      row =
        insert_pending_row(integration,
          sync_state: "locally_created",
          provider_calendar_id: "/cal/tymeslot/",
          provider_event_id: "/cal/tymeslot/queue-event-uid.ics"
        )

      ReqTest.stub(:tymeslot_http, fn conn ->
        assert conn.request_path =~ "/cal/tymeslot/"
        refute conn.request_path =~ "/cal/personal/"
        Conn.send_resp(conn, 201, "")
      end)

      assert :ok = OfflineQueue.flush(integration, @client)

      assert Repo.reload!(row).sync_state == "synced"
    end

    test "falls back to the connection's first path for a legacy row with no provider_calendar_id" do
      # The fallback reads `integration.calendar_paths`, so this integration
      # (not the client) needs the multi-calendar list.
      multi_integration =
        insert(:calendar_integration,
          provider: "caldav",
          calendar_paths: ["/cal/personal/", "/cal/tymeslot/"]
        )

      # provider_calendar_id is NOT NULL at the DB level, so a row that
      # predates per-row tagging is represented by an empty string rather
      # than nil.
      row =
        insert_pending_row(multi_integration,
          sync_state: "locally_created",
          provider_calendar_id: ""
        )

      ReqTest.stub(:tymeslot_http, fn conn ->
        assert conn.request_path =~ "/cal/personal/"
        Conn.send_resp(conn, 201, "")
      end)

      assert :ok = OfflineQueue.flush(multi_integration, @client)

      assert Repo.reload!(row).sync_state == "synced"
    end
  end

  describe "flush/2 — empty queue" do
    test "is a no-op when no rows are pending", %{integration: integration} do
      # All rows are synced — no HTTP traffic should happen.
      _row = insert_pending_row(integration, sync_state: "synced")

      ReqTest.stub(:tymeslot_http, fn _conn ->
        flunk("OfflineQueue.flush must not touch the network when queue is empty")
      end)

      assert :ok = OfflineQueue.flush(integration, @client)
    end

    test "ignores rows belonging to other integrations", %{integration: integration} do
      # A row on another integration must not be flushed.
      other = insert(:calendar_integration, provider: "caldav", calendar_paths: ["/cal/"])
      _row = insert_pending_row(other, sync_state: "locally_modified")

      ReqTest.stub(:tymeslot_http, fn _conn ->
        flunk("OfflineQueue.flush touched network for rows belonging to another integration")
      end)

      assert :ok = OfflineQueue.flush(integration, @client)
    end
  end

  describe "query helpers" do
    test "list_pending returns non-synced rows in updated_at order",
         %{integration: integration} do
      older = insert_pending_row(integration, uid: "older", sync_state: "locally_modified")
      _synced = insert_pending_row(integration, uid: "synced-1", sync_state: "synced")
      newer = insert_pending_row(integration, uid: "newer", sync_state: "locally_created")

      # Force an ordering difference independent of insert order
      SQL.query!(
        Repo,
        "UPDATE provider_calendar_events SET updated_at = $1 WHERE id = $2",
        [~U[2026-04-14 00:00:00.000000Z], older.id]
      )

      SQL.query!(
        Repo,
        "UPDATE provider_calendar_events SET updated_at = $1 WHERE id = $2",
        [~U[2026-04-15 00:00:00.000000Z], newer.id]
      )

      uids =
        integration.id
        |> QueueQueries.list_pending()
        |> Enum.map(& &1.uid)

      assert uids == ["older", "newer"]
    end

    test "mark_synced clears queue fields and updates etag",
         %{integration: integration} do
      row = insert_pending_row(integration, sync_state: "locally_modified", etag: "\"stale\"")

      assert {:ok, :updated} =
               QueueQueries.mark_synced(integration.id, row.uid, "\"fresh\"")

      reloaded = Repo.reload!(row)
      assert reloaded.sync_state == "synced"
      assert reloaded.sync_attempts == 0
      assert reloaded.sync_last_error == nil
      assert reloaded.etag == "\"fresh\""
    end

    test "mark_sync_failed increments sync_attempts and sets sync_last_error without changing sync_state",
         %{integration: integration} do
      row = insert_pending_row(integration, sync_state: "locally_modified")

      assert :ok =
               QueueQueries.mark_sync_failed(
                 integration.id,
                 row.uid,
                 "502 Bad Gateway"
               )

      after_first = Repo.reload!(row)
      assert after_first.sync_state == "locally_modified"
      assert after_first.sync_attempts == 1
      assert after_first.sync_last_error == "502 Bad Gateway"

      assert :ok =
               QueueQueries.mark_sync_failed(
                 integration.id,
                 row.uid,
                 "503 Service Unavailable"
               )

      after_second = Repo.reload!(row)
      assert after_second.sync_state == "locally_modified"
      assert after_second.sync_attempts == 2
      assert after_second.sync_last_error == "503 Service Unavailable"
    end

    test "upsert_queue_entry applies on-conflict update — second call's sync_state wins",
         %{integration: integration} do
      base_attrs = %{
        calendar_integration_id: integration.id,
        uid: "upsert-test-uid",
        provider: "caldav",
        provider_calendar_id: "/cal/",
        provider_event_id: "/cal/upsert-test-uid.ics",
        summary: "Upsert Test",
        start_at: ~U[2026-04-15 14:00:00.000000Z],
        end_at: ~U[2026-04-15 15:00:00.000000Z],
        all_day: false,
        timezone: "UTC",
        synced_at: ~U[2026-04-15 00:00:00.000000Z],
        etag: "\"etag-v1\"",
        sync_state: "locally_created"
      }

      assert {:ok, 1} = QueueQueries.upsert_queue_entry(base_attrs)

      first =
        Repo.get_by!(ProviderCalendarEventSchema,
          uid: "upsert-test-uid",
          calendar_integration_id: integration.id
        )

      assert first.sync_state == "locally_created"

      updated_attrs = Map.put(base_attrs, :sync_state, "locally_modified")
      assert {:ok, 1} = QueueQueries.upsert_queue_entry(updated_attrs)

      second =
        Repo.get_by!(ProviderCalendarEventSchema,
          uid: "upsert-test-uid",
          calendar_integration_id: integration.id
        )

      assert second.sync_state == "locally_modified"
    end
  end
end
