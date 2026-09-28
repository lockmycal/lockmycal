defmodule TymeslotWeb.Live.Scheduling.BookingFormPrefillTest do
  @moduledoc """
  A signed-in visitor's own name and email are filled into the booking form;
  an anonymous visitor gets an empty one.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :scheduling
  @moduletag :live

  import Mox
  import Tymeslot.Factory

  alias Phoenix.ConnTest
  alias Tymeslot.Infrastructure.AvailabilityCache
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.TestMocks

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)
    RateLimiter.clear_all()
    AvailabilityCache.clear_all()
    TestMocks.setup_all_mocks()

    user = insert(:user)

    profile =
      insert(:profile,
        user: user,
        username: "prefillhost",
        booking_theme: "1",
        timezone: "Etc/UTC"
      )

    schedule =
      insert(:availability_schedule,
        profile: profile,
        is_default: true,
        advance_booking_days: 30,
        min_advance_hours: 0,
        buffer_minutes: 0
      )

    Enum.each(1..7, fn day_of_week ->
      insert(:weekly_availability,
        schedule: schedule,
        day_of_week: day_of_week,
        is_available: true,
        start_time: ~T[09:00:00],
        end_time: ~T[17:00:00]
      )
    end)

    meeting_type =
      insert(:meeting_type,
        user: user,
        duration_minutes: 45,
        name: "Deep Dive",
        is_active: true
      )

    insert(:calendar_integration, user: user, is_active: true)

    date = Date.to_string(Date.add(Date.utc_today(), 3))

    %{profile: profile, meeting_type: meeting_type, date: date}
  end

  import Tymeslot.AuthTestHelpers, only: [log_in_user: 2]

  @tag :capture_log
  test "a signed-in visitor gets their name and email pre-filled",
       %{conn: conn, profile: profile, date: date} do
    visitor = insert(:user, email: "visitor@example.com")

    insert(:profile,
      user: visitor,
      username: "prefillvisitor",
      full_name: "Vera Visitor",
      phone: "+420 123 456 789",
      company: "Visitor s.r.o."
    )

    {:ok, _view, html} =
      live(
        log_in_user(ConnTest.init_test_session(conn, %{}), visitor),
        "/#{profile.username}/deep-dive/book?date=#{date}&time=10:00%20AM"
      )

    assert html =~ ~s(value="Vera Visitor")
    assert html =~ ~s(value="visitor@example.com")
    assert html =~ ~s(value="+420 123 456 789")
    assert html =~ ~s(value="Visitor s.r.o.")
  end

  @tag :capture_log
  test "falls back to the account name when the profile has no full name",
       %{conn: conn, profile: profile, date: date} do
    visitor = insert(:user, email: "oauth@example.com", name: "Oscar Auth")
    insert(:profile, user: visitor, username: "prefilloauth", full_name: nil)

    {:ok, _view, html} =
      live(
        log_in_user(ConnTest.init_test_session(conn, %{}), visitor),
        "/#{profile.username}/deep-dive/book?date=#{date}&time=10:00%20AM"
      )

    assert html =~ ~s(value="Oscar Auth")
  end

  @tag :capture_log
  test "an anonymous visitor gets an empty form", %{conn: conn, profile: profile, date: date} do
    {:ok, _view, html} =
      live(conn, "/#{profile.username}/deep-dive/book?date=#{date}&time=10:00%20AM")

    refute html =~ "visitor@example.com"
    refute html =~ ~s(value="Vera Visitor")
  end
end
