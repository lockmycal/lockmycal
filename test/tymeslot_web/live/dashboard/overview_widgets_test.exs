defmodule TymeslotWeb.Dashboard.OverviewWidgetsTest do
  @moduledoc """
  The Overview's KPI row and side widgets: quick actions, integrations,
  7-day analytics and widgets registered through
  `Tymeslot.Dashboard.OverviewWidget`.
  """
  # Not async: toggles global app env (analytics flag, registered widgets).
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :dashboard

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  defmodule TestWidget do
    @moduledoc false
    @behaviour Tymeslot.Dashboard.OverviewWidget

    use Phoenix.Component

    @impl Tymeslot.Dashboard.OverviewWidget
    def id, do: :test_plan

    @impl Tymeslot.Dashboard.OverviewWidget
    def render(user) do
      assigns = %{email: user.email}

      ~H"""
      <div class="card-glass">Plan widget for {@email}</div>
      """
    end
  end

  defmodule HiddenWidget do
    @moduledoc false
    @behaviour Tymeslot.Dashboard.OverviewWidget

    @impl Tymeslot.Dashboard.OverviewWidget
    def id, do: :hidden

    @impl Tymeslot.Dashboard.OverviewWidget
    def render(_user), do: nil
  end

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now(:second))
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")

    for key <- [:booking_analytics_enabled, :dashboard_overview_extra_widgets] do
      previous = Application.fetch_env(:tymeslot, key)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:tymeslot, key, value)
          :error -> Application.delete_env(:tymeslot, key)
        end
      end)
    end

    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "shows the KPI row with this week's bookings, approvals and open polls",
       %{conn: conn, user: user} do
    insert(:meeting,
      organizer_user_id: user.id,
      organizer_email: user.email,
      status: "awaiting_approval"
    )

    insert(:poll, user: user)

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    assert has_element?(view, "#overview-kpi-today")
    assert has_element?(view, "#overview-kpi-week")
    assert view |> element("#overview-kpi-approval") |> render() =~ "1"
    assert view |> element("#overview-kpi-polls") |> render() =~ "1"
    assert has_element?(view, "#overview-kpi-approval[href='/dashboard/meetings']")
  end

  test "offers creating a meeting, opening the calendar's create form", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    assert has_element?(view, "#overview-create-meeting[href='/dashboard?create=1']")
  end

  test "flags an integration that needs reauthorisation", %{conn: conn, user: user} do
    insert(:calendar_integration, user: user, needs_reauth: true)

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    assert view |> element("#overview-integration-calendars") |> render() =~ "1 needs attention"
    assert view |> element("#overview-integration-video") |> render() =~ "Not connected"
  end

  test "shows the 7-day analytics widget only when analytics is enabled", %{conn: conn} do
    Application.put_env(:tymeslot, :booking_analytics_enabled, false)
    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")
    refute has_element?(view, "#overview-analytics")

    Application.put_env(:tymeslot, :booking_analytics_enabled, true)
    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")
    assert has_element?(view, "#overview-analytics")
    assert has_element?(view, "#overview-analytics svg[role='img']")
  end

  test "renders registered extension widgets, skipping ones that return nil",
       %{conn: conn, user: user} do
    Application.put_env(:tymeslot, :dashboard_overview_extra_widgets, [TestWidget, HiddenWidget])

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    assert view |> element("#overview-widget-test_plan") |> render() =~
             "Plan widget for #{user.email}"

    refute view |> element("#overview-widget-hidden") |> render() =~ "card-glass"
  end
end
