defmodule TymeslotWeb.Dashboard.CalendarGrid.EventColourLiveViewTest do
  use TymeslotWeb.LiveCase, async: true

  @moduletag :calendar
  @moduletag :live

  import Mox
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Plug.Test
  alias Tymeslot.Integrations.Calendar.ProviderCalendarEventQueries

  setup :verify_on_exit!

  # The provider write runs in a Task; allow for a busy test machine.
  @task_timeout 5_000

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")
    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user}
  end

  describe "event colour override" do
    setup %{user: user} do
      integration = insert(:calendar_integration, user: user, is_active: true)
      today = Date.utc_today()

      event =
        insert_event(integration, %{
          summary: "Design Review",
          start_at: DateTime.new!(today, ~T[10:00:00], "Etc/UTC"),
          end_at: DateTime.new!(today, ~T[11:00:00], "Etc/UTC"),
          all_day: false,
          colour: nil
        })

      {:ok, integration: integration, event: event}
    end

    test "picking a colour updates the colour bar in the modal (optimistic)", %{
      conn: conn,
      event: event
    } do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/calendar")
      modal_html = lv |> element("[id^='event-#{event.id}-']") |> render_click()
      refute color_bar_class(modal_html) =~ "bg-calendar-tomato"

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("update_event_colour", %{"colour" => "tomato"})

      assert color_bar_class(html) =~ "bg-calendar-tomato"
    end

    test "persists the colour to the cache on a successful provider write", %{
      conn: conn,
      integration: integration,
      event: event
    } do
      test_pid = self()

      expect(Tymeslot.CalendarMock, :update_event, fn _uid, payload, _context ->
        send(test_pid, {:provider_update, self(), payload})
        :ok
      end)

      {:ok, lv, _html} = live(conn, ~p"/dashboard/calendar")
      lv |> element("[id^='event-#{event.id}-']") |> render_click()

      lv
      |> element("#calendar-grid")
      |> render_hook("update_event_colour", %{"colour" => "blueberry"})

      assert_receive {:provider_update, task_pid, payload}, @task_timeout
      assert payload.colour == "blueberry"

      # The cache is written by the same Task once the provider has answered.
      ref = Process.monitor(task_pid)
      assert_receive {:DOWN, ^ref, :process, ^task_pid, _reason}, @task_timeout

      assert {:ok, cached} = ProviderCalendarEventQueries.get_by_uid(integration.id, event.uid)
      assert cached.colour == "blueberry"
    end

    test "selecting Default clears an existing override (optimistic)", %{
      conn: conn,
      integration: integration
    } do
      today = Date.utc_today()

      coloured =
        insert_event(integration, %{
          summary: "Already Coloured",
          start_at: DateTime.new!(today, ~T[12:00:00], "Etc/UTC"),
          end_at: DateTime.new!(today, ~T[13:00:00], "Etc/UTC"),
          all_day: false,
          colour: "grape"
        })

      {:ok, lv, _html} = live(conn, ~p"/dashboard/calendar")
      modal_html = lv |> element("[id^='event-#{coloured.id}-']") |> render_click()
      # The grape override starts painted on the modal's colour bar.
      assert color_bar_class(modal_html) =~ "bg-calendar-grape"

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("update_event_colour", %{"colour" => "default"})

      refute color_bar_class(html) =~ "bg-calendar-grape"
    end
  end

  # The modal has no colour-picker UI of its own (colour can only be changed
  # via `update_event_colour`, e.g. from the calendar grid); reading the
  # header's colour bar class out is how a test observes the optimistic
  # update took effect.
  defp color_bar_class(html) do
    bar =
      html
      |> Floki.parse_document!()
      |> Floki.find("[data-testid='event-colour-bar']")
      |> List.first()

    case bar do
      nil -> ""
      element -> element |> Floki.attribute("class") |> List.first()
    end
  end

  defp insert_event(integration, attrs) do
    insert(:provider_calendar_event, Map.merge(%{calendar_integration: integration}, attrs))
  end
end
