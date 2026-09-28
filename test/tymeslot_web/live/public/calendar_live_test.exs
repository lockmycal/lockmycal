defmodule TymeslotWeb.Public.CalendarLiveTest do
  @moduledoc """
  Coverage for `TymeslotWeb.Public.CalendarLive` — the public, read-only
  `/:username/calendar` page. Previously had no test coverage at all, which
  is why a post-rebase regression (`@profile.time_format` — `time_format`
  moved off the `Profile` schema onto `calendar_preferences` during the
  v1.7.0 → v1.8.1 rebase, see `CalendarGrid.get_user_time_format/2`) reached
  production undetected: `KeyError: key :time_format not found`, crashing
  the page for any organiser who links to it.
  """
  use TymeslotWeb.LiveCase, async: false

  @moduletag :calendar

  import Tymeslot.Factory

  test "renders without crashing for an organiser with a busy event", %{conn: conn} do
    user = insert(:user)

    profile =
      insert(:profile,
        user: user,
        username: "public-cal-organiser",
        timezone: "Etc/UTC"
      )

    integration = insert(:calendar_integration, user: user, is_active: true)

    now = DateTime.utc_now(:microsecond)

    insert(:provider_calendar_event,
      calendar_integration: integration,
      start_at: now,
      end_at: DateTime.add(now, 3600, :second)
    )

    {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")

    assert html =~ "Busy"
    assert has_element?(view, ".public-calendar-container")
  end

  test "renders without crashing when the organiser has no busy events", %{conn: conn} do
    user = insert(:user)

    profile =
      insert(:profile,
        user: user,
        username: "public-cal-quiet",
        timezone: "Etc/UTC"
      )

    {:ok, _view, html} = live(conn, ~p"/#{profile.username}/calendar")

    assert html =~ "public-calendar-container"
  end

  test "shows the not-found state for an unknown username", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/no-such-organiser/calendar")

    assert html =~ "No such organiser."
  end

  test "only says the calendar is not public when the organiser switched it off", %{
    conn: conn
  } do
    profile = insert(:profile, username: "public-cal-hidden", public_calendar_enabled: false)

    {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")

    assert html =~ "This calendar is not public."
    refute has_element?(view, ".public-calendar-card")
  end

  describe "language switching" do
    test "persists locale change from dropdown across a fresh connection", %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-locale",
          timezone: "Etc/UTC"
        )

      {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")
      assert html =~ ~s(data-locale="en")

      view |> element("button[phx-click='toggle_language_dropdown']") |> render_click()

      # follow_redirect returns {:ok, conn} for the external redirect
      # change_locale now issues (needed so LocalePlug persists it to session).
      {:ok, conn} =
        view
        |> element("button[phx-click='change_locale'][phx-value-locale='cs']")
        |> render_click()
        |> follow_redirect(conn)

      {:ok, new_view, _html} = live(conn)
      assert render(new_view) =~ ~s(data-locale="cs")

      # A brand new connection (session/cookies carried via recycle) should
      # still be Czech — proof the choice reached the session, not just the
      # in-memory socket of the LiveView that handled the click.
      conn = recycle(conn)
      {:ok, _final_view, html} = live(conn, ~p"/#{profile.username}/calendar")
      assert html =~ ~s(data-locale="cs")
    end
  end

  describe "events the calendar marks as free" do
    setup do
      user = insert(:user)

      profile =
        insert(:profile, user: user, username: "public-cal-free", timezone: "Etc/UTC")

      integration = insert(:calendar_integration, user: user, is_active: true)
      %{profile: profile, integration: integration}
    end

    test "show as a distinct 'Not blocking' chip with a legend, never a title", %{
      conn: conn,
      profile: profile,
      integration: integration
    } do
      now = DateTime.utc_now(:microsecond)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Secret invitation",
        transparency: "transparent",
        start_at: now,
        end_at: DateTime.add(now, 1800, :second)
      )

      {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")

      assert html =~ "public-calendar-chip--non-blocking"
      assert html =~ "Not blocking ("
      refute html =~ "Secret invitation"
      assert has_element?(view, ".public-calendar-legend-non-blocking")
    end

    test "leave no chip or legend when every event is busy", %{
      conn: conn,
      profile: profile,
      integration: integration
    } do
      now = DateTime.utc_now(:microsecond)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        transparency: "opaque",
        start_at: now,
        end_at: DateTime.add(now, 1800, :second)
      )

      {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")

      refute html =~ "public-calendar-chip--non-blocking"
      refute has_element?(view, ".public-calendar-legend-non-blocking")
    end
  end

  describe "meetings awaiting approval" do
    test "render as a distinct 'Pending approval' chip, never a title or attendee", %{
      conn: conn
    } do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-pending",
          timezone: "Etc/UTC"
        )

      now = DateTime.utc_now(:microsecond)

      insert(:meeting,
        organizer_user_id: user.id,
        status: "awaiting_approval",
        title: "Secret strategy session",
        attendee_name: "Should Not Leak",
        start_time: now,
        end_time: DateTime.add(now, 3600, :second)
      )

      {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")

      assert html =~ "Pending approval"
      assert html =~ "public-calendar-chip--pending"
      refute html =~ "Secret strategy session"
      refute html =~ "Should Not Leak"
      assert has_element?(view, ".public-calendar-legend-pending")
    end

    test "don't render a Pending approval chip/legend when there are none", %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-no-pending",
          timezone: "Etc/UTC"
        )

      {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")

      refute html =~ "Pending approval"
      refute has_element?(view, ".public-calendar-legend-pending")
    end
  end

  describe "chip ordering and overflow" do
    test "renders a day's busy chips sorted by start time ascending, regardless of insertion order",
         %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-sorted",
          timezone: "Etc/UTC"
        )

      integration = insert(:calendar_integration, user: user, is_active: true)
      day_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

      # Inserted out of chronological order on purpose.
      for hour <- [11, 9, 10] do
        start_at = DateTime.add(day_start, hour * 3600, :second)

        insert(:provider_calendar_event,
          calendar_integration: integration,
          start_at: start_at,
          end_at: DateTime.add(start_at, 3600, :second)
        )
      end

      {:ok, _view, html} = live(conn, ~p"/#{profile.username}/calendar")

      first = elem(:binary.match(html, "9:00 AM"), 0)
      second = elem(:binary.match(html, "10:00 AM"), 0)
      third = elem(:binary.match(html, "11:00 AM"), 0)

      assert first < second
      assert second < third
    end

    test "lists the hidden events' times in the '+x more' chip's hover tooltip", %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-overflow",
          timezone: "Etc/UTC"
        )

      integration = insert(:calendar_integration, user: user, is_active: true)
      day_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

      # 5 same-day events, one more than @max_chips (4) — the 5th (latest)
      # should overflow into the "+1 more" tooltip.
      for hour <- [8, 9, 10, 11, 12] do
        start_at = DateTime.add(day_start, hour * 3600, :second)

        insert(:provider_calendar_event,
          calendar_integration: integration,
          start_at: start_at,
          end_at: DateTime.add(start_at, 3600, :second)
        )
      end

      {:ok, view, html} = live(conn, ~p"/#{profile.username}/calendar")

      assert html =~ "+1 more"

      more_chip_html = view |> element(".public-calendar-chip-more") |> render()

      assert more_chip_html =~ "12:00 PM"
      refute more_chip_html =~ "8:00 AM"
    end
  end

  describe "public calendar visible hours" do
    test "hides busy and pending-approval chips outside the configured window", %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-visible-hours",
          timezone: "Etc/UTC",
          public_calendar_visible_from: ~T[07:00:00],
          public_calendar_visible_to: ~T[18:00:00]
        )

      integration = insert(:calendar_integration, user: user, is_active: true)
      day_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

      # Entirely before the window -> hidden.
      early_start = DateTime.add(day_start, 5 * 3600, :second)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: early_start,
        end_at: DateTime.add(early_start, 3600, :second)
      )

      # Inside the window -> shown.
      visible_start = DateTime.add(day_start, 10 * 3600, :second)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: visible_start,
        end_at: DateTime.add(visible_start, 3600, :second)
      )

      # A pending-approval meeting entirely before the window -> hidden too.
      insert(:meeting,
        organizer_user_id: user.id,
        status: "awaiting_approval",
        start_time: DateTime.add(day_start, 4 * 3600, :second),
        end_time: DateTime.add(day_start, 5 * 3600, :second)
      )

      {:ok, _view, html} = live(conn, ~p"/#{profile.username}/calendar")

      assert html =~ "10:00 AM"
      refute html =~ "5:00 AM"
      refute html =~ "Pending approval"
    end

    test "shows busy chips at any hour when no window is configured", %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-no-window",
          timezone: "Etc/UTC"
        )

      integration = insert(:calendar_integration, user: user, is_active: true)
      day_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")
      start_at = DateTime.add(day_start, 3 * 3600, :second)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: start_at,
        end_at: DateTime.add(start_at, 3600, :second)
      )

      {:ok, _view, html} = live(conn, ~p"/#{profile.username}/calendar")

      assert html =~ "3:00 AM"
    end
  end

  describe "historical events" do
    test "hides a past busy chip by default but still shows today's", %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-no-history",
          timezone: "Etc/UTC"
        )

      integration = insert(:calendar_integration, user: user, is_active: true)

      past_day = Date.add(Date.utc_today(), -35)
      past_start = DateTime.new!(past_day, ~T[10:00:00], "Etc/UTC")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: past_start,
        end_at: DateTime.add(past_start, 3600, :second)
      )

      today_start = DateTime.new!(Date.utc_today(), ~T[14:00:00], "Etc/UTC")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: today_start,
        end_at: DateTime.add(today_start, 3600, :second)
      )

      past_month = month_param(past_day)
      {:ok, _view, past_html} = live(conn, ~p"/#{profile.username}/calendar?month=#{past_month}")
      refute past_html =~ "10:00 AM"

      {:ok, _view, today_html} = live(conn, ~p"/#{profile.username}/calendar")
      assert today_html =~ "2:00 PM"
    end

    test "shows past busy chips once the organiser opts in", %{conn: conn} do
      user = insert(:user)

      profile =
        insert(:profile,
          user: user,
          username: "public-cal-with-history",
          timezone: "Etc/UTC",
          public_calendar_show_historical_events: true
        )

      integration = insert(:calendar_integration, user: user, is_active: true)

      past_day = Date.add(Date.utc_today(), -35)
      past_start = DateTime.new!(past_day, ~T[10:00:00], "Etc/UTC")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        start_at: past_start,
        end_at: DateTime.add(past_start, 3600, :second)
      )

      past_month = month_param(past_day)
      {:ok, _view, html} = live(conn, ~p"/#{profile.username}/calendar?month=#{past_month}")

      assert html =~ "10:00 AM"
    end
  end

  defp month_param(date), do: "#{date.year}-#{String.pad_leading("#{date.month}", 2, "0")}"
end
