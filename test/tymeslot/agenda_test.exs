defmodule Tymeslot.AgendaTest do
  @moduledoc """
  Tests for the dashboard agenda: merging bookings with synced calendar events,
  deduplication, filtering, timezone bucketing, and the hero fallback.
  """

  use Tymeslot.DataCase, async: true
  @moduletag :calendar

  alias Tymeslot.Agenda
  alias Tymeslot.Agenda.Day
  alias Tymeslot.Agenda.Entry
  alias Tymeslot.CalendarGrid
  alias Tymeslot.Integrations.Calendar.Appearance
  alias Tymeslot.Utils.DateTimeUtils

  setup do
    today = Date.utc_today()
    {:ok, user: insert(:user), today: today, tomorrow: Date.add(today, 1)}
  end

  describe "day_agenda/2 merging" do
    test "merges confirmed bookings and synced calendar events", %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Client call")
      external_event(user, at(tomorrow, ~T[13:00:00]), summary: "Team sync")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert day.has_calendar?
      assert "Client call" in titles(day)
      assert "Team sync" in titles(day)
    end

    test "tags each entry with the calendar it belongs to", %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Client call")

      integration = insert(:calendar_integration, user: user, name: "Work Google")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Team sync",
        start_at: at(tomorrow, ~T[13:00:00]),
        end_at: at(tomorrow, ~T[14:00:00]),
        all_day: false
      )

      day = Agenda.day_agenda(user, "Etc/UTC")

      booking = Enum.find(entries(day), &(&1.title == "Client call"))
      synced = Enum.find(entries(day), &(&1.title == "Team sync"))

      # A booking is a Tymeslot entry (no synced calendar); a synced event carries
      # the integration's name so the UI can say which calendar it came from.
      assert booking.calendar == nil
      assert synced.calendar == "Work Google"
    end

    test "names the calendar within an account with several in use", %{
      user: user,
      tomorrow: tomorrow
    } do
      integration =
        insert(:calendar_integration,
          user: user,
          name: "Company account",
          provider: "caldav",
          calendar_paths: ["/cal/work/", "/cal/team/"],
          calendar_list: [
            %{"id" => "/cal/work/", "path" => "/cal/work/", "name" => "Work", "selected" => true},
            %{"id" => "/cal/team/", "path" => "/cal/team/", "name" => "Team", "selected" => true}
          ]
        )

      insert(:provider_calendar_event,
        calendar_integration: integration,
        provider_calendar_id: "/cal/team/",
        summary: "Standup",
        start_at: at(tomorrow, ~T[09:00:00]),
        end_at: at(tomorrow, ~T[09:15:00]),
        all_day: false
      )

      # A booking is named after the calendar it was written to.
      booking(user, at(tomorrow, ~T[12:00:00]),
        title: "Client call",
        calendar_integration_id: integration.id,
        calendar_path: "/cal/work/"
      )

      day = Agenda.day_agenda(user, "Etc/UTC")

      # Two calendars in use under one account: each is qualified by it.
      assert Enum.find(entries(day), &(&1.title == "Standup")).calendar ==
               "Company account - Team"

      assert Enum.find(entries(day), &(&1.title == "Client call")).calendar ==
               "Company account - Work"
    end

    test "names an account with a single calendar in use after the account alone", %{
      user: user,
      tomorrow: tomorrow
    } do
      integration =
        insert(:calendar_integration,
          user: user,
          name: "Itopo",
          provider: "caldav",
          calendar_paths: ["/cal/work/"],
          calendar_list: [
            %{"id" => "/cal/work/", "path" => "/cal/work/", "name" => "Work", "selected" => true},
            %{"id" => "/cal/old/", "path" => "/cal/old/", "name" => "Old", "selected" => false}
          ]
        )

      insert(:provider_calendar_event,
        calendar_integration: integration,
        provider_calendar_id: "/cal/work/",
        summary: "Standup",
        start_at: at(tomorrow, ~T[09:00:00]),
        end_at: at(tomorrow, ~T[09:15:00]),
        all_day: false
      )

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert Enum.find(entries(day), &(&1.title == "Standup")).calendar == "Itopo"
    end

    test "falls back to the integration's name for a calendar it doesn't list", %{
      user: user,
      tomorrow: tomorrow
    } do
      integration = insert(:calendar_integration, user: user, name: "Work Google")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        provider_calendar_id: "unlisted",
        summary: "Team sync",
        start_at: at(tomorrow, ~T[13:00:00]),
        end_at: at(tomorrow, ~T[14:00:00]),
        all_day: false
      )

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert Enum.find(entries(day), &(&1.title == "Team sync")).calendar == "Work Google"
    end

    test "carries a booking's attendee and their email", %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]),
        title: "Client call",
        attendee_name: "Ada Lovelace",
        attendee_email: "ada@example.com"
      )

      assert [%Entry{who: "Ada Lovelace", who_email: "ada@example.com"}] =
               entries(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "names a titleless booking and leaves a missing event title for the presentation to label",
         %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "  ")
      external_event(user, at(tomorrow, ~T[13:00:00]), summary: nil)

      assert titles(Agenda.day_agenda(user, "Etc/UTC")) == ["Meeting", nil]
    end

    test "surfaces the earliest timed entry as the hero and excludes it from the groups",
         %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[14:00:00]), title: "Later")
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Sooner")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert day.next.title == "Sooner"
      assert Enum.map(day.tomorrow, & &1.title) == ["Later"]
      refute "Sooner" in Enum.map(day.tomorrow, & &1.title)
    end
  end

  describe "day_agenda/2 who a booking is with" do
    # A group meeting keeps no attendee of its own, so the agenda had no one
    # to name and showed the booking with nobody.
    defp group_booking(user, start, participants) do
      meeting =
        insert(:group_meeting,
          organizer_email: user.email,
          title: "Workshop",
          capacity: 4,
          start_time: start,
          end_time: DateTime.add(start, 3600, :second)
        )

      for {name, live?} <- participants do
        insert(:participant,
          meeting: meeting,
          name: name,
          cancelled_at: if(live?, do: nil, else: DateTime.utc_now(:second))
        )
      end

      meeting
    end

    test "a group meeting with one live participant names them", %{user: user, tomorrow: tomorrow} do
      group_booking(user, at(tomorrow, ~T[12:00:00]), [{"Ada", true}, {"Gone", false}])

      assert [%{title: "Workshop", who: "Ada"}] = entries(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "a group meeting with several live participants counts them", %{
      user: user,
      tomorrow: tomorrow
    } do
      group_booking(user, at(tomorrow, ~T[12:00:00]), [
        {"Ada", true},
        {"Ben", true},
        {"Gone", false}
      ])

      assert [%{who: "2 participants"}] = entries(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "a solo booking still names its attendee", %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), attendee_name: "Solo Sam")

      assert [%{who: "Solo Sam"}] = entries(Agenda.day_agenda(user, "Etc/UTC"))
    end
  end

  describe "day_agenda/2 deduplication and filtering" do
    test "drops the synced copy of a booking the agenda doesn't list itself", %{
      user: user,
      tomorrow: tomorrow
    } do
      slot = at(tomorrow, ~T[12:00:00])
      booking(user, slot, status: "cancelled", calendar_uid: "cancelled-1@tymeslot.com")

      external_event(user, slot,
        summary: "Synced copy",
        uid: "cancelled-1@tymeslot.com",
        created_by_tymeslot: true
      )

      assert Day.empty?(Agenda.day_agenda(user, "Etc/UTC"))
    end

    # The CalDAV queue stamps `created_by_tymeslot` on an event the organiser
    # created or edited in the dashboard calendar too; with no booking behind
    # it, it is the organiser's own appointment.
    test "keeps a Tymeslot-stamped event that no booking stands behind", %{
      user: user,
      tomorrow: tomorrow
    } do
      external_event(user, at(tomorrow, ~T[09:00:00]),
        summary: "Sync meeting",
        created_by_tymeslot: true
      )

      assert "Sync meeting" in titles(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "drops external events matching a booking's provider_event_id",
         %{user: user, tomorrow: tomorrow} do
      slot = at(tomorrow, ~T[12:00:00])
      booking(user, slot, title: "Real booking", provider_event_id: "evt-123")
      external_event(user, slot, summary: "Duplicate", provider_event_id: "evt-123")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert [entry] = entries(day)
      assert entry.title == "Real booking"
      assert entry.source == :tymeslot
    end

    test "drops the CalDAV copy of a booking, which shares only its UID",
         %{user: user, tomorrow: tomorrow} do
      slot = at(tomorrow, ~T[12:00:00])
      uid = "abc123@tymeslot.com"

      # A CalDAV booking carries no provider_event_id; its synced copy is keyed
      # by href. Only the UID links the two.
      booking(user, slot, title: "Real booking", calendar_uid: uid, provider_event_id: nil)

      external_event(user, slot,
        summary: "Duplicate",
        uid: uid,
        provider_event_id: "/cal/primary/#{uid}.ics",
        created_by_tymeslot: false
      )

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert [entry] = entries(day)
      assert entry.title == "Real booking"
      assert entry.source == :tymeslot
    end

    test "excludes transparent (free) external events", %{user: user, tomorrow: tomorrow} do
      external_event(user, at(tomorrow, ~T[12:00:00]),
        summary: "Focus time",
        transparency: "transparent"
      )

      assert Day.empty?(Agenda.day_agenda(user, "Etc/UTC"))
    end

    # The sync leaves a deselected calendar's rows in the cache until pruning
    # runs, so the agenda has to honour the selection itself, as the grid does.
    test "excludes events from a calendar the user has deselected", %{
      user: user,
      tomorrow: tomorrow
    } do
      integration =
        insert(:calendar_integration,
          user: user,
          provider: "caldav",
          calendar_paths: ["/cal/work/"],
          calendar_list: [
            %{"id" => "/cal/work/", "path" => "/cal/work/", "selected" => true},
            %{"id" => "/cal/personal/", "path" => "/cal/personal/", "selected" => false}
          ]
        )

      for {summary, path, hour} <- [
            {"Work Meeting", "/cal/work/", 12},
            {"Personal Errand", "/cal/personal/", 11}
          ] do
        insert(:provider_calendar_event,
          calendar_integration: integration,
          summary: summary,
          start_at: at(tomorrow, Time.new!(hour, 0, 0)),
          end_at: at(tomorrow, Time.new!(hour + 1, 0, 0)),
          all_day: false,
          provider_event_id: path <> "evt.ics"
        )
      end

      assert titles(Agenda.day_agenda(user, "Etc/UTC")) == ["Work Meeting"]
    end

    test "excludes cancelled external events", %{user: user, tomorrow: tomorrow} do
      external_event(user, at(tomorrow, ~T[12:00:00]), summary: "Called off", status: "cancelled")

      assert Day.empty?(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "excludes pending and cancelled bookings", %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Pending", status: "pending")
      booking(user, at(tomorrow, ~T[13:00:00]), title: "Cancelled", status: "cancelled")

      assert Day.empty?(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "excludes a confirmed booking with a pending reschedule request, but keeps a plain confirmed one",
         %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]),
        title: "Voided by reschedule request",
        reschedule_requested_at: DateTime.utc_now()
      )

      booking(user, at(tomorrow, ~T[13:00:00]), title: "Still confirmed")

      day = Agenda.day_agenda(user, "Etc/UTC")

      refute "Voided by reschedule request" in titles(day)
      assert "Still confirmed" in titles(day)
    end
  end

  describe "day_agenda/2 all-day events" do
    test "places all-day events in their day group and never as the hero",
         %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Timed")
      all_day_event(user, tomorrow, summary: "Company offsite")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert day.next.title == "Timed"
      assert offsite = Enum.find(day.tomorrow, &(&1.title == "Company offsite"))
      assert offsite.all_day?
    end
  end

  describe "day_agenda/2 calendar presence and hero fallback" do
    test "works without any calendar integration", %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Solo booking")

      day = Agenda.day_agenda(user, "Etc/UTC")

      refute day.has_calendar?
      assert "Solo booking" in titles(day)
    end

    test "excludes events from an inactive integration and reports no calendar presence",
         %{user: user, tomorrow: tomorrow} do
      integration = insert(:calendar_integration, user: user, is_active: false)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Should not appear",
        start_at: at(tomorrow, ~T[12:00:00]),
        end_at: at(tomorrow, ~T[13:00:00]),
        all_day: false
      )

      day = Agenda.day_agenda(user, "Etc/UTC")

      refute "Should not appear" in titles(day)
      assert Day.empty?(day)
      refute day.has_calendar?
    end

    test "excludes events from an integration in hidden_integration_ids",
         %{user: user, tomorrow: tomorrow} do
      integration = insert(:calendar_integration, user: user, is_active: true)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Should not appear",
        start_at: at(tomorrow, ~T[12:00:00]),
        end_at: at(tomorrow, ~T[13:00:00]),
        all_day: false
      )

      CalendarGrid.save_preferences(user.id, %{hidden_integration_ids: [integration.id]})

      day = Agenda.day_agenda(user, "Etc/UTC")

      refute "Should not appear" in titles(day)
      assert Day.empty?(day)
      refute day.has_calendar?
    end

    test "excludes events from a hidden calendar but keeps calendar presence",
         %{user: user, tomorrow: tomorrow} do
      integration = insert(:calendar_integration, user: user, is_active: true)

      insert(:provider_calendar_event,
        calendar_integration: integration,
        provider_calendar_id: "primary",
        summary: "Should not appear",
        start_at: at(tomorrow, ~T[12:00:00]),
        end_at: at(tomorrow, ~T[13:00:00]),
        all_day: false
      )

      Appearance.set_hidden(user.id, integration.id, "primary", true)

      day = Agenda.day_agenda(user, "Etc/UTC")

      refute "Should not appear" in titles(day)
      # Unlike hiding the whole integration, hiding one calendar inside it
      # doesn't affect calendar presence — the integration itself is still
      # active and connected.
      assert day.has_calendar?
    end

    test "keeps the hero populated with the next appointment beyond tomorrow",
         %{user: user, today: today} do
      booking(user, at(Date.add(today, 5), ~T[12:00:00]), title: "Next week")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert day.next.title == "Next week"
      assert day.later?
      assert day.today == []
      assert day.tomorrow == []
    end

    test "is empty when nothing is upcoming", %{user: user} do
      assert Day.empty?(Agenda.day_agenda(user, "Etc/UTC"))
    end
  end

  describe "day_agenda/2 timezone bucketing" do
    test "buckets entries by the user's timezone", %{user: user, tomorrow: tomorrow} do
      # Late-evening UTC lands on a different calendar day in a far-ahead zone.
      start = at(tomorrow, ~T[23:30:00])
      booking(user, start, title: "Edge of day")

      expected_utc = local_date(start, "Etc/UTC")
      expected_ahead = local_date(start, "Pacific/Kiritimati")

      assert Agenda.day_agenda(user, "Etc/UTC").next.day == expected_utc
      assert Agenda.day_agenda(user, "Pacific/Kiritimati").next.day == expected_ahead
      refute expected_utc == expected_ahead
    end

    test "falls back to UTC for a blank timezone", %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Whenever")

      assert Agenda.day_agenda(user, nil).timezone == "Etc/UTC"
      assert Agenda.day_agenda(user, "").timezone == "Etc/UTC"
    end
  end

  describe "day_agenda/2 multi-day and in-progress overlap" do
    test "keeps a multi-day all-day event on every day it spans", %{
      user: user,
      today: today
    } do
      # A block that started yesterday and runs for several days — a week of leave.
      multi_day_all_day_event(user, Date.add(today, -1), Date.add(today, 3), summary: "On leave")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert Enum.any?(day.today, &(&1.title == "On leave"))
      assert Enum.any?(day.tomorrow, &(&1.title == "On leave"))
    end
  end

  # --- Helpers ---------------------------------------------------------------

  # No meeting information by default, so an entry is titled by its own title
  # (what these tests identify it by) under the default title source.
  defp booking(user, start, opts) do
    {status, opts} = Keyword.pop(opts, :status, "confirmed")
    opts = Keyword.put_new(opts, :attendee_message, nil)

    insert(
      :meeting,
      [
        organizer_email: user.email,
        start_time: start,
        end_time: DateTime.add(start, 3600, :second),
        status: status
      ] ++ opts
    )
  end

  defp external_event(user, start, opts) do
    integration = insert(:calendar_integration, user: user)

    insert(
      :provider_calendar_event,
      [
        calendar_integration: integration,
        start_at: start,
        end_at: DateTime.add(start, 3600, :second),
        all_day: false
      ] ++ opts
    )
  end

  defp all_day_event(user, date, opts) do
    integration = insert(:calendar_integration, user: user)

    insert(
      :provider_calendar_event,
      [
        calendar_integration: integration,
        all_day: true,
        start_date: date,
        end_date: Date.add(date, 1),
        start_at: nil,
        end_at: nil
      ] ++ opts
    )
  end

  defp multi_day_all_day_event(user, start_date, end_date, opts) do
    integration = insert(:calendar_integration, user: user)

    insert(
      :provider_calendar_event,
      [
        calendar_integration: integration,
        all_day: true,
        start_date: start_date,
        end_date: end_date,
        start_at: nil,
        end_at: nil
      ] ++ opts
    )
  end

  defp at(date, time), do: DateTime.new!(date, time, "Etc/UTC")

  defp local_date(datetime, tz),
    do: datetime |> DateTimeUtils.convert_to_timezone(tz) |> DateTime.to_date()

  defp entries(%Day{} = day),
    do: Enum.reject([day.next | day.today ++ day.tomorrow], &is_nil/1)

  defp titles(day), do: day |> entries() |> Enum.map(& &1.title)
end
