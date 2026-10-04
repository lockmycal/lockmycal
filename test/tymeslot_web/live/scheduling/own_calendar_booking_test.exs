defmodule TymeslotWeb.Live.Scheduling.OwnCalendarBookingTest do
  @moduledoc """
  A signed-in booker is offered their own calendar copy of the booking on the
  form, and a signed-out one is told there, before booking, that signing in
  would do that (`Tymeslot.Meetings.BookerCalendar`).
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :scheduling
  @moduletag :live

  import Mox
  import Phoenix.LiveViewTest
  import Tymeslot.Factory
  import Tymeslot.ThemeBookingFlowHelpers
  import Tymeslot.AuthTestHelpers, only: [log_in_user: 2]

  alias Phoenix.ConnTest
  alias Tymeslot.Meetings.BookerCalendar
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo
  alias Tymeslot.TestMocks

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)

    TestMocks.setup_email_mocks()
    TestMocks.setup_subscription_mocks()

    Tymeslot.CalendarMock
    |> stub(:get_events_for_range_fresh, fn _user_id, _start_date, _end_date -> {:ok, []} end)
    |> stub(:get_booking_integration_info, fn _user_id -> {:error, :no_integration} end)

    :ok
  end

  @timezone "America/New_York"
  @themes %{"1" => "quill", "2" => "rhythm"}

  defp visitor(choice \\ :ask) do
    visitor = insert(:user, email: "booker-#{System.unique_integer([:positive])}@example.com")
    insert(:profile, user: visitor, save_bookings_to_own_calendar: choice)
    insert(:calendar_integration, user: visitor, name: "Booker calendar")
    visitor
  end

  defp open_as(conn, visitor, profile) do
    {:ok, view, _html} =
      live(
        log_in_user(ConnTest.init_test_session(conn, %{}), visitor),
        ~p"/#{profile.username}?timezone=#{@timezone}"
      )

    view
  end

  defp submit(view, extra) do
    view
    |> form("form[data-testid='booking-form']", %{
      "booking" =>
        Map.merge(
          %{
            "name" => "Booker",
            "email" => "booker@example.com",
            "phone" => "+1 555 200 3000",
            "message" => "Hello, looking forward to it!"
          },
          extra
        )
    })
    |> render_submit()

    eventually(fn -> has_element?(view, "[data-testid='confirmation-heading']") end,
      timeout: 10_000
    )

    render(view)
  end

  for {theme_id, theme} <- @themes do
    describe "#{theme} theme" do
      @tag :capture_log
      test "a signed-in booker who ticks the box gets the copy, and the choice is remembered",
           %{conn: conn} do
        %{user: organizer, profile: profile} =
          seed_booking_account(unquote(theme_id), "own-cal-#{unquote(theme)}", @timezone)

        visitor = visitor()
        view = open_as(conn, visitor, profile)
        advance_to_booking_form(view, unquote(theme))

        assert render(view) =~ "Booker calendar"

        html =
          submit(view, %{
            "save_to_own_calendar" => "true",
            "remember_own_calendar_choice" => "true"
          })

        meeting = Repo.get_by!(MeetingSchema, organizer_user_id: organizer.id)
        assert meeting.booker_user_id == visitor.id
        assert BookerCalendar.choice(visitor.id) == :always
        refute html =~ "own-calendar-hint"
      end

      @tag :capture_log
      test "a signed-in booker who unticks the box gets no copy", %{conn: conn} do
        %{user: organizer, profile: profile} =
          seed_booking_account(unquote(theme_id), "own-cal-no-#{unquote(theme)}", @timezone)

        visitor = visitor()
        view = open_as(conn, visitor, profile)
        advance_to_booking_form(view, unquote(theme))

        submit(view, %{"save_to_own_calendar" => "false"})

        meeting = Repo.get_by!(MeetingSchema, organizer_user_id: organizer.id)
        assert meeting.booker_user_id == nil
        assert BookerCalendar.choice(visitor.id) == :ask
      end

      @tag :capture_log
      test "a remembered choice is applied without asking", %{conn: conn} do
        %{user: organizer, profile: profile} =
          seed_booking_account(unquote(theme_id), "own-cal-always-#{unquote(theme)}", @timezone)

        visitor = visitor(:always)
        view = open_as(conn, visitor, profile)
        advance_to_booking_form(view, unquote(theme))

        refute has_element?(view, "[data-testid='own-calendar-field']")

        submit(view, %{})

        assert Repo.get_by!(MeetingSchema, organizer_user_id: organizer.id).booker_user_id ==
                 visitor.id
      end

      @tag :capture_log
      test "a signed-out booker is told before booking that signing in would save it",
           %{conn: conn} do
        %{user: organizer, profile: profile} =
          seed_booking_account(unquote(theme_id), "own-cal-anon-#{unquote(theme)}", @timezone)

        {:ok, view, _html} = live(conn, ~p"/#{profile.username}?timezone=#{@timezone}")
        advance_to_booking_form(view, unquote(theme))

        refute has_element?(view, "[data-testid='own-calendar-field']")

        # The sign-in link comes back to this very form, with the slot chosen.
        href =
          view
          |> element("[data-testid='own-calendar-sign-in']")
          |> render()
          |> Floki.parse_fragment!()
          |> Floki.attribute("href")
          |> hd()

        %URI{path: "/auth/login", query: query} = URI.parse(href)
        return_to = URI.decode_query(query)["return_to"]
        %URI{path: return_path, query: return_query} = URI.parse(return_to)

        assert return_path =~ ~r"^/#{profile.username}/[^/]+/book$"
        assert %{"date" => _date, "time" => _time} = URI.decode_query(return_query)

        html = submit(view, %{})

        refute html =~ "own-calendar-hint"
        assert Repo.get_by!(MeetingSchema, organizer_user_id: organizer.id).booker_user_id == nil
      end

      @tag :capture_log
      test "a signed-in booker sees no sign-in hint", %{conn: conn} do
        %{profile: profile} =
          seed_booking_account(unquote(theme_id), "own-cal-in-#{unquote(theme)}", @timezone)

        view = open_as(conn, visitor(), profile)
        advance_to_booking_form(view, unquote(theme))

        refute has_element?(view, "[data-testid='own-calendar-hint']")
      end
    end
  end
end
