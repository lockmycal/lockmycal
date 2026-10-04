defmodule TymeslotWeb.Dashboard.CalendarSettings.DefaultCalendarTest do
  @moduledoc """
  Choosing the default calendar on the Calendars page, and the remembered
  answer to whether bookings made on other people's pages are saved to it.
  """
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :dashboard

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Meetings.BookerCalendar
  alias Tymeslot.Profiles.ProfileQueries

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now(:second))
    profile = insert(:profile, user: user, timezone: "Etc/UTC")

    first = insert(:calendar_integration, user: user, name: "First calendar")
    second = insert(:calendar_integration, user: user, name: "Second calendar")
    {:ok, _profile} = ProfileQueries.set_primary_calendar_integration(user.id, first.id)

    {:ok,
     conn: log_in_user(conn, user), user: user, profile: profile, first: first, second: second}
  end

  test "marks the default calendar and lets another become it", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/dashboard/calendar-integration")

    assert has_element?(view, "[data-testid='default-calendar-badge']")

    view
    |> element("button[data-testid='set-default-calendar'][phx-value-id='#{ctx.second.id}']")
    |> render_click()

    {:ok, profile} = ProfileQueries.get_by_user_id(ctx.user.id)
    assert profile.primary_calendar_integration_id == ctx.second.id

    refute has_element?(
             view,
             "button[data-testid='set-default-calendar'][phx-value-id='#{ctx.second.id}']"
           )

    assert has_element?(
             view,
             "button[data-testid='set-default-calendar'][phx-value-id='#{ctx.first.id}']"
           )
  end

  describe "a connection with several calendars" do
    setup ctx do
      several =
        insert(:calendar_integration,
          user: ctx.user,
          name: "SOGo",
          calendar_list: [
            %{"id" => "/cal/personal/", "name" => "Personal", "selected" => true},
            %{"id" => "/cal/work/", "name" => "Work", "selected" => true},
            %{"id" => "/cal/shared/", "name" => "Shared", "selected" => true, "read_only" => true}
          ]
        )

      %{several: several}
    end

    test "asks which of them is the default", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/dashboard/calendar-integration")

      view
      |> element("button[data-testid='set-default-calendar'][phx-value-id='#{ctx.several.id}']")
      |> render_click()

      # Nothing changes until a calendar is chosen, and only writable ones are offered.
      assert {ctx.first.id, nil} == Calendar.default_calendar(ctx.user.id)
      assert has_element?(view, "#default-calendar-choice option[value='/cal/work/']")
      refute has_element?(view, "#default-calendar-choice option[value='/cal/shared/']")

      view
      |> form("#default-calendar-form", %{"calendar_id" => "/cal/work/"})
      |> render_submit()

      assert {ctx.several.id, "/cal/work/"} == Calendar.default_calendar(ctx.user.id)
      assert view |> element("[data-testid='default-calendar-badge']") |> render() =~ "Work"

      # The default connection keeps the action, to pick another of its calendars.
      assert has_element?(
               view,
               "button[data-testid='set-default-calendar'][phx-value-id='#{ctx.several.id}']"
             )
    end
  end

  test "a calendar that cannot take bookings is not offered as the default", ctx do
    flagged = insert(:calendar_integration, user: ctx.user, needs_reauth: true)

    {:ok, view, _html} = live(ctx.conn, ~p"/dashboard/calendar-integration")

    refute has_element?(
             view,
             "button[data-testid='set-default-calendar'][phx-value-id='#{flagged.id}']"
           )
  end

  test "changes the remembered own-bookings choice", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/dashboard/calendar-integration")

    view
    |> element("#own-bookings-form")
    |> render_change(%{"choice" => "never"})

    assert BookerCalendar.choice(ctx.user.id) == :never

    view
    |> element("#own-bookings-form")
    |> render_change(%{"choice" => "ask"})

    assert BookerCalendar.choice(ctx.user.id) == :ask
  end

  test "ignores a choice it does not know", ctx do
    {:ok, view, _html} = live(ctx.conn, ~p"/dashboard/calendar-integration")

    view
    |> element("#own-bookings-form")
    |> render_change(%{"choice" => "sometimes"})

    assert BookerCalendar.choice(ctx.user.id) == :ask
  end
end
