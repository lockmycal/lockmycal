defmodule TymeslotWeb.Dashboard.CalendarSettings.ConnectionLimitTest do
  @moduledoc """
  The Calendars page under a calendar connection limit: the usage notice, the
  disabled connect buttons, and the refusal when a connect is attempted
  anyway. Without a limit (Core's default checker) none of it renders.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :integrations
  @moduletag :calendar
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.ConfigTestHelpers
  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationQueries

  setup :setup_dashboard_user

  defmodule LimitOneChecker do
    @moduledoc false
    @behaviour Tymeslot.Features.CheckerBehaviour

    @impl Tymeslot.Features.CheckerBehaviour
    def check_access(_user_id, _feature), do: :ok

    @impl Tymeslot.Features.CheckerBehaviour
    def limit(_user_id, :calendar_integrations), do: 1
    def limit(_user_id, _resource), do: :unlimited
  end

  test "no notice without a limit", %{conn: conn, user: user} do
    insert(:calendar_integration, user: user)

    {:ok, _view, html} = live(conn, ~p"/dashboard/calendar-integration")

    refute html =~ "connection-limit-notice"
  end

  describe "with a limit of one connection" do
    setup do
      with_config(:tymeslot, :feature_access_checker, LimitOneChecker)
      :ok
    end

    test "below the limit, shows usage and keeps connecting enabled", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/dashboard/calendar-integration")

      assert html =~ "Active calendars: 0 of 1."
      refute has_element?(view, "button[phx-click='show_picker'][disabled]")
    end

    test "at the limit, disables connecting and refuses a connect attempt", %{
      conn: conn,
      user: user
    } do
      insert(:calendar_integration, user: user)

      {:ok, view, html} = live(conn, ~p"/dashboard/calendar-integration")

      assert html =~ "Active calendars: 1 of 1."
      assert html =~ "maximum number of connected calendars"
      assert has_element?(view, "button[phx-click='show_picker'][disabled]")

      # A stale page (or a crafted event) still can't open a connect form.
      # The picker modal is always in the DOM, so its tiles stay clickable.
      view
      |> element("button[phx-click='connect_provider'][phx-value-provider='ics_url']")
      |> render_click()

      refute has_element?(view, "#calendar-subscription-form")
      assert CalendarIntegrationQueries.count_for_user(user.id) == 1
    end
  end

  describe "with a limit of one and a paused calendar" do
    setup do
      with_config(:tymeslot, :feature_access_checker, LimitOneChecker)
      :ok
    end

    test "the paused calendar's switch is disabled and explained", %{conn: conn, user: user} do
      insert(:calendar_integration, user: user)
      paused = insert(:calendar_integration, user: user, is_active: false)

      {:ok, view, html} = live(conn, ~p"/dashboard/calendar-integration")

      assert html =~ "pause an active one first"
      assert has_element?(view, "#toggle-#{paused.id}[disabled]")
    end
  end
end
