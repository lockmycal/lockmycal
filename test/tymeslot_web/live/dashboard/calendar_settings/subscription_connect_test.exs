defmodule TymeslotWeb.Dashboard.CalendarSettings.SubscriptionConnectTest do
  @moduledoc """
  Composition test for subscribing to a published calendar feed from the
  integrations dashboard: picking the tile, submitting the feed URL, and what
  the resulting integration is and is not allowed to be.

  The HTTP boundary is stubbed at `Tymeslot.HTTPClientMock`, the same seam the
  CalDAV connect flow uses, so the pre-save feed probe runs end to end without
  a real publisher.
  """

  use TymeslotWeb.LiveCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :integration
  @moduletag :integrations
  @moduletag :calendar
  @moduletag :live

  import Mox
  import Phoenix.LiveViewTest
  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema
  alias Tymeslot.Integrations.Calendar.Runtime.ClientManager
  alias Tymeslot.Integrations.CalendarPrimary
  alias Tymeslot.Repo
  alias Tymeslot.Security.Encryption
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.Workers.SyncIcsCalendarWorker

  setup :verify_on_exit!
  setup :setup_dashboard_user

  @feed_url "https://outlook.office365.com/owa/calendar/secret-token/calendar.ics"

  @ics """
  BEGIN:VCALENDAR
  VERSION:2.0
  PRODID:-//Example Corp//Publisher//EN
  BEGIN:VEVENT
  UID:published-event@example.com
  DTSTART:20260810T090000Z
  DTEND:20260810T100000Z
  SUMMARY:Busy
  END:VEVENT
  END:VCALENDAR
  """

  defp stub_feed do
    stub(Tymeslot.HTTPClientMock, :get, fn _url, _headers, _opts ->
      {:ok, %Req.Response{status: 200, body: @ics, headers: %{}}}
    end)
  end

  defp subscribe(view, url \\ @feed_url) do
    view
    |> element("button[phx-click='connect_provider'][phx-value-provider='ics_url']")
    |> render_click()

    view
    |> form("#calendar-subscription-form", %{
      "integration" => %{"name" => "Work calendar", "url" => url}
    })
    |> render_submit()

    # `add_subscription` runs the feed probe off the socket's process (see
    # `ConfigViewComponent.handle_event/3`), which comfortably exceeds
    # `render_async/1`'s 100ms default under load.
    render_async(view, 5000)
  end

  # `picker_groups/2` (`CalendarSettingsComponent`) files each provider under
  # its group's `<h3>` label, followed by the grid `<div>` holding that
  # group's tiles. `has_element?/2` can't scope on that adjacency — LiveView
  # 1.2's test selector engine (`LazyHTML`) has no text-matching pseudo-class
  # — so this parses the markup directly with `Floki` (which does) and finds
  # the provider button inside the `<div>` immediately following the group's
  # `<h3>`, rather than trusting the page-wide text a mislabelled tile would
  # still satisfy.
  defp group_tile?(html, group_label, provider) do
    html
    |> Floki.parse_document!()
    |> Floki.find(
      ~s|h3:fl-contains("#{group_label}") + div button[phx-value-provider='#{provider}']|
    )
    |> Enum.any?()
  end

  describe "subscribing to a feed" do
    @tag :capture_log
    test "the tile is filed under subscriptions, not under CalDAV servers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/calendar-integration")

      assert html =~ "Calendar subscriptions"
      assert group_tile?(html, "Calendar subscriptions", "ics_url")
      refute group_tile?(html, "CalDAV servers", "ics_url")
      refute group_tile?(html, "Calendar subscriptions", "caldav")
    end

    @tag :capture_log
    test "submitting a feed URL persists the subscription and closes the modal", %{
      conn: conn,
      user: user
    } do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      # The success flash is raised by the config component but rendered by the
      # parent LiveView, so `render_async/2` can return the component's own
      # re-render before the parent has painted the flash. Snapshotting once
      # makes this test position-dependent: it passes when earlier tests have
      # warmed the flow and fails when it runs first (seed 0). Poll instead.
      wait_until(fn -> render(view) =~ "Calendar integration added successfully" end)

      added = render(view)

      assert added =~ "Work calendar"
      refute has_element?(view, "#calendar-subscription-form")

      assert integration =
               Repo.get_by(CalendarIntegrationSchema, user_id: user.id, provider: "ics_url")

      assert integration.name == "Work calendar"

      assert_enqueued(
        worker: SyncIcsCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end

    @tag :capture_log
    test "the feed URL is stored encrypted and only its origin is left in the clear", %{
      conn: conn,
      user: user
    } do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      integration =
        Repo.get_by(CalendarIntegrationSchema, user_id: user.id, provider: "ics_url")

      # The secret path must not survive anywhere readable on the row.
      assert integration.base_url == "https://outlook.office365.com"
      refute integration.base_url =~ "secret-token"
      refute to_string(integration.provider_account_id) =~ "secret-token"
      assert Encryption.decrypt(integration.subscription_url_encrypted) == @feed_url
    end

    @tag :capture_log
    test "the subscription's only calendar is read-only", %{conn: conn, user: user} do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      integration =
        Repo.get_by(CalendarIntegrationSchema, user_id: user.id, provider: "ics_url")

      assert [calendar] = integration.calendar_list
      assert calendar.read_only
      assert Calendar.writable_calendars(integration.calendar_list) == []
    end

    @tag :capture_log
    test "a subscription is never promoted to the primary calendar", %{conn: conn, user: user} do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      # Even as the user's first and only integration: a primary that cannot
      # receive a booking would break every booking write.
      assert {:error, _reason} = CalendarPrimary.get_primary_calendar_integration(user.id)
    end

    @tag :capture_log
    test "a subscription is never resolved as the booking integration", %{
      conn: conn,
      user: user
    } do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      assert ClientManager.get_booking_integration_info(user.id) == {:error, :no_integration}
      assert ClientManager.booking_client(user.id) == nil
    end

    @tag :capture_log
    test "the connected row is marked read-only and hides controls that do not apply", %{
      conn: conn
    } do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      # The connected row is painted by the parent LiveView, which only reloads
      # the hub's integration list when it handles the `{:integration_added,
      # :calendar}` announcement `handle_async` sends. `render_async/2` waits on
      # the probe task, not on that message, so its own render call can reach
      # the mailbox first and hand back pre-refresh markup. Poll, for the same
      # reason the success flash above is polled rather than snapshotted.
      wait_until(fn -> render(view) =~ "Read-only" end)

      # Rename and colour still apply to a subscription, so the modal stays
      # reachable — but its calendar-selection grid does not, since there is
      # only ever one synthetic calendar, always selected.
      assert has_element?(view, "button[phx-click='manage_calendars']")

      view
      |> element("button[phx-click='manage_calendars']")
      |> render_click()

      refute has_element?(view, "button[phx-click='toggle_calendar_selection']")

      # The feed URL is editable through the same "Reconnect" action every
      # other provider uses — CaldavReconnectModal makes its username/password
      # fields optional for a subscription instead of hiding the whole thing.
      assert has_element?(view, "button[phx-click='show_reconnect']")
    end

    @tag :capture_log
    test "an unreachable feed is refused with an error rather than saved", %{
      conn: conn,
      user: user
    } do
      stub(Tymeslot.HTTPClientMock, :get, fn _url, _headers, _opts ->
        {:ok, %Req.Response{status: 404, body: "", headers: %{}}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      result = subscribe(view)

      refute result =~ "Calendar integration added successfully"
      refute Repo.get_by(CalendarIntegrationSchema, user_id: user.id, provider: "ics_url")
    end

    @tag :capture_log
    test "the same feed cannot be subscribed to twice", %{conn: conn, user: user} do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      {:ok, second_view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      result = subscribe(second_view)

      assert result =~ "already exists"

      subscriptions =
        Enum.count(
          Repo.all(CalendarIntegrationSchema),
          &(&1.user_id == user.id and &1.provider == "ics_url")
        )

      assert subscriptions == 1
    end

    @tag :capture_log
    test "a genuine double submission is refused with a changeset error rather than a crash", %{
      user: user
    } do
      # Widens the gap between the duplicate check and the insert enough that
      # both concurrent submissions pass the check before either commits,
      # reproducing the race a double-submit (or two browser tabs) can hit.
      stub(Tymeslot.HTTPClientMock, :get, fn _url, _headers, _opts ->
        Process.sleep(50)
        {:ok, %Req.Response{status: 200, body: @ics, headers: %{}}}
      end)

      params = %{"name" => "Race calendar", "url" => @feed_url}
      test_pid = self()

      results =
        [1, 2]
        |> Enum.map(fn _attempt ->
          Task.async(fn ->
            allow(Tymeslot.HTTPClientMock, test_pid, self())
            Calendar.create_subscription_with_validation(user.id, params)
          end)
        end)
        |> Enum.map(&Task.await(&1, 5_000))

      assert Enum.count(results, &match?({:ok, _integration}, &1)) == 1
      assert Enum.count(results, &match?({:error, {:changeset, _changeset}}, &1)) == 1

      subscriptions =
        Enum.count(
          Repo.all(CalendarIntegrationSchema),
          &(&1.user_id == user.id and &1.provider == "ics_url")
        )

      assert subscriptions == 1
    end
  end

  describe "updating a subscription's feed URL via the Reconnect action" do
    @new_feed_url "https://calendar.google.com/calendar/ical/other-secret/basic.ics"

    setup do
      RateLimiter.clear_all()
      :ok
    end

    defp open_reconnect_modal(view, integration_id) do
      view
      |> element("button[phx-click='show_reconnect'][phx-value-id='#{integration_id}']")
      |> render_click()
    end

    @tag :capture_log
    test "a reachable new URL replaces the old one and a resync is enqueued", %{
      conn: conn,
      user: user
    } do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      integration =
        Repo.get_by(CalendarIntegrationSchema, user_id: user.id, provider: "ics_url")

      open_reconnect_modal(view, integration.id)

      view
      |> form("#caldav-reconnect-credentials-form", %{"reconnect" => %{"url" => @new_feed_url}})
      |> render_submit()

      # `Flash.info/1` forwards the message to the parent LiveView's
      # `handle_info/2` rather than putting it on this component's own
      # socket (see `TymeslotWeb.Live.Shared.Flash`'s moduledoc), so it only
      # shows up on a fresh `render/1`, not on `render_submit/1`'s return.
      assert render(view) =~ "Calendar reconnected"

      updated = Repo.get!(CalendarIntegrationSchema, integration.id)
      assert Encryption.decrypt(updated.subscription_url_encrypted) == @new_feed_url
      assert updated.base_url == "https://calendar.google.com"
      refute updated.provider_account_id == integration.provider_account_id

      assert_enqueued(
        worker: SyncIcsCalendarWorker,
        args: %{"calendar_integration_id" => integration.id}
      )
    end

    @tag :capture_log
    test "an unreachable new URL is refused and the old URL is kept", %{
      conn: conn,
      user: user
    } do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)

      integration =
        Repo.get_by(CalendarIntegrationSchema, user_id: user.id, provider: "ics_url")

      stub(Tymeslot.HTTPClientMock, :get, fn _url, _headers, _opts ->
        {:ok, %Req.Response{status: 404, body: "", headers: %{}}}
      end)

      open_reconnect_modal(view, integration.id)

      view
      |> form("#caldav-reconnect-credentials-form", %{"reconnect" => %{"url" => @new_feed_url}})
      |> render_submit()

      unchanged = Repo.get!(CalendarIntegrationSchema, integration.id)
      assert Encryption.decrypt(unchanged.subscription_url_encrypted) == @feed_url
    end

    @tag :capture_log
    test "a URL already used by another of the user's subscriptions is refused", %{
      conn: conn,
      user: user
    } do
      stub_feed()

      {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")
      subscribe(view)
      subscribe(view, @new_feed_url)

      # Sorted by id: `Repo.all/1` has no ORDER BY, so the rows can come back in
      # either order, and `second` must be the subscription created second.
      [first, second] =
        CalendarIntegrationSchema
        |> Repo.all()
        |> Enum.filter(&(&1.user_id == user.id))
        |> Enum.sort_by(& &1.id)

      open_reconnect_modal(view, second.id)

      result =
        view
        |> form("#caldav-reconnect-credentials-form", %{"reconnect" => %{"url" => @feed_url}})
        |> render_submit()

      assert result =~ "already subscribed"

      unchanged = Repo.get!(CalendarIntegrationSchema, second.id)
      assert Encryption.decrypt(unchanged.subscription_url_encrypted) == @new_feed_url
      assert first.id != second.id
    end
  end
end
