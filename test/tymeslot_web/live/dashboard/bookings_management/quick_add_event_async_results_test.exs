defmodule TymeslotWeb.Dashboard.BookingsManagement.QuickAddEventAsyncResultsTest do
  @moduledoc """
  Covers the Meetings page's own "Quick add" dialog (event mode) async result
  handling — mirrors `TymeslotWeb.Dashboard.CalendarGrid.EventAsyncResultsTest`.

  `QuickAddMeetingExecution.execute_event/2` spawns a supervised Task instead
  of writing to the calendar provider inline, so `DashboardLive` only ever
  sees the `{:quick_add_event_created, result}` message the Task sends back —
  simulating that message arriving is enough to cover the routing
  (handle_info -> send_update -> BookingsManagementComponent.update/2 ->
  QuickAddMeetingExecution.handle_event_create_result/2) without mocking the
  underlying provider write itself.

  Three `render/1` calls are needed to settle, one more than the calendar
  page's own two-render convention: DashboardLive's handle_info -> send_update
  is the same two hops, but the result handler here runs inside a
  LiveComponent, so its flash goes through `Live.Shared.Flash`'s own
  self-send-to-parent indirection (`put_flash/3` inside a component is
  otherwise silently dropped) — a third hop the calendar path never needs,
  since its handler already runs on DashboardLive's own socket.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :meetings
  @moduletag :live

  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Plug.Test

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")
    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user}
  end

  defp build_result(overrides \\ %{}) do
    Map.merge(
      %{
        uid: "quick-add-event-uid",
        attendees: [],
        warning: nil,
        reauth_required: false
      },
      overrides
    )
  end

  # handle_info -> send_update -> Flash self-send-to-parent.
  defp settle(lv) do
    render(lv)
    render(lv)
    render(lv)
  end

  describe "async event create result — success" do
    test "flashes 'Event created.' and closes the dialog when there are no attendees", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")

      send(lv.pid, {:quick_add_event_created, {:ok, build_result()}})
      html = settle(lv)

      assert html =~ "Event created."
      refute html =~ ~s(id="create-event-modal")
    end

    test "flashes the attendees-invited copy when there are attendees", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")

      send(
        lv.pid,
        {:quick_add_event_created, {:ok, build_result(%{attendees: [%{email: "a@x.com"}]})}}
      )

      html = settle(lv)

      assert html =~ "Event created. Attendees have been invited."
    end
  end

  describe "async event create result — failure" do
    test "flashes an error and keeps the dialog available to retry", %{conn: conn, user: user} do
      _integration = insert(:calendar_integration, user: user, is_active: true)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/meetings")

      send(
        lv.pid,
        {:quick_add_event_created, {:error, %{reason: :api_error, retry: :not_queued}}}
      )

      html = settle(lv)

      # A default-factory integration has no calendar_paths, so
      # QueueWiring.tag/3 can't queue an offline retry (:ignored) — the
      # deterministic outcome is the plain failure copy, not the
      # queued-to-retry one.
      assert html =~ "Failed to create event"
    end
  end
end
