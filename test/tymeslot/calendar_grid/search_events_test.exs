defmodule Tymeslot.CalendarGrid.SearchEventsTest do
  @moduledoc """
  Covers `CalendarGrid.search_events/4`: the calendar-selection guard (a
  deselected calendar's cached rows must not be able to crowd a selected
  match out of the limited result set) and the search of the bookings the
  grid shows without a provider copy.
  """

  use Tymeslot.DataCase, async: true

  @moduletag :calendar
  @moduletag :unit

  import Tymeslot.Factory

  alias Tymeslot.CalendarGrid

  test "a deselected calendar's rows do not crowd a selected match out of the results" do
    user = insert(:user)

    visible_integration = insert(:calendar_integration, user: user, is_active: true)

    deselected_integration =
      insert(:calendar_integration,
        user: user,
        is_active: true,
        provider: "caldav",
        calendar_paths: [],
        calendar_list: [%{"id" => "/cal/team/", "path" => "/cal/team/", "selected" => false}]
      )

    # More than the (batch-sized) limit of older, deselected-calendar matches,
    # all starting before the one selected-calendar match.
    for n <- 1..3 do
      insert(:provider_calendar_event,
        calendar_integration: deselected_integration,
        summary: "Standup #{n}",
        start_at: DateTime.add(~U[2026-06-01 09:00:00Z], n, :hour),
        provider_event_id: "/cal/team/evt-#{n}.ics"
      )
    end

    kept =
      insert(:provider_calendar_event,
        calendar_integration: visible_integration,
        summary: "Standup kickoff",
        start_at: ~U[2026-06-02 09:00:00Z]
      )

    result =
      CalendarGrid.search_events(
        user.id,
        "standup",
        [visible_integration, deselected_integration],
        limit: 3
      )

    assert [%{id: id}] = result
    assert id == kept.id
  end

  test "an unbounded run of deselected-calendar rows still can't crowd a selected match out" do
    user = insert(:user)

    visible_integration = insert(:calendar_integration, user: user, is_active: true)

    deselected_integration =
      insert(:calendar_integration,
        user: user,
        is_active: true,
        provider: "caldav",
        calendar_paths: [],
        calendar_list: [%{"id" => "/cal/team/", "path" => "/cal/team/", "selected" => false}]
      )

    # More than four times the limit of older, deselected-calendar matches:
    # a paged fetch capped at a fixed number of extra pages would give up
    # before ever reaching the selected match.
    for n <- 1..13 do
      insert(:provider_calendar_event,
        calendar_integration: deselected_integration,
        summary: "Standup #{n}",
        start_at: DateTime.add(~U[2026-06-01 09:00:00Z], n, :hour),
        provider_event_id: "/cal/team/evt-#{n}.ics"
      )
    end

    kept =
      insert(:provider_calendar_event,
        calendar_integration: visible_integration,
        summary: "Standup kickoff",
        start_at: ~U[2026-06-02 09:00:00Z]
      )

    result =
      CalendarGrid.search_events(
        user.id,
        "standup",
        [visible_integration, deselected_integration],
        limit: 3
      )

    assert [%{id: id}] = result
    assert id == kept.id
  end

  describe "bookings the grid shows without a provider copy" do
    # One organiser cannot have two confirmed meetings at the same time, so
    # each booking gets its own hour unless the test says when.
    defp booking(user, attrs) do
      start_time =
        Keyword.get_lazy(attrs, :start_time, fn ->
          DateTime.utc_now()
          |> DateTime.add(System.unique_integer([:positive]) * 2, :hour)
          |> DateTime.truncate(:second)
        end)

      insert(
        :meeting,
        Keyword.merge(
          [
            organizer_user_id: user.id,
            start_time: start_time,
            end_time: DateTime.add(start_time, 30, :minute)
          ],
          attrs
        )
      )
    end

    test "are found by their title, meeting information and booker" do
      user = insert(:user)
      by_title = booking(user, title: "Test sync 21:02", attendee_message: nil)
      by_message = booking(user, title: "Intro call", attendee_message: "Please test sync first")
      by_booker = booking(user, title: "Other", attendee_name: "Synchro Tester")
      _unrelated = booking(user, title: "Lunch", attendee_message: nil, attendee_name: "Anna")

      assert [%{kind: :booking, meeting_id: id}] =
               CalendarGrid.search_events(user.id, "21:02", [])

      assert id == by_title.id

      ids = user.id |> CalendarGrid.search_events("test sync", []) |> Enum.map(& &1.meeting_id)
      assert by_title.id in ids and by_message.id in ids
      refute by_booker.id in ids

      assert [%{meeting_id: booker_id}] = CalendarGrid.search_events(user.id, "synchro", [])
      assert booker_id == by_booker.id
    end

    test "are named under the organiser's title source" do
      user = insert(:user)
      booking(user, title: "Call with Jane", attendee_message: "Quarterly review\nmore text")

      assert [%{summary: "Quarterly review"}] =
               CalendarGrid.search_events(user.id, "quarterly", [])

      assert [%{summary: "Call with Jane"}] =
               CalendarGrid.search_events(user.id, "jane", [], title_source: "meeting_type")
    end

    test "leave out another organiser's bookings and cancelled ones" do
      user = insert(:user)
      other = insert(:user)
      booking(other, title: "Test sync other")
      booking(user, title: "Test sync cancelled", status: "cancelled")

      assert CalendarGrid.search_events(user.id, "test sync", []) == []
    end

    test "are not listed twice when their provider copy is cached, even in a hidden calendar" do
      user = insert(:user)
      integration = insert(:calendar_integration, user: user, is_active: true)

      synced =
        booking(user, title: "Test sync copy", provider_event_id: "gcal-1", calendar_uid: "uid-1")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Test sync copy",
        uid: "uid-1",
        provider_event_id: "gcal-1"
      )

      # Findable through the provider copy, not as a second, booking entry.
      assert [%{summary: "Test sync copy"} = hit] =
               CalendarGrid.search_events(user.id, "test sync", [integration])

      refute Map.get(hit, :kind) == :booking

      # The copy is in a calendar the user switched off: the booking stays hidden.
      assert [] =
               CalendarGrid.search_events(user.id, "test sync", [integration],
                 hidden_integration_ids: [integration.id]
               )

      assert synced.id
    end

    test "are ordered with the provider events by start time and share the limit" do
      user = insert(:user)
      integration = insert(:calendar_integration, user: user, is_active: true)
      early = DateTime.add(DateTime.utc_now(), 1, :day)

      booking(user,
        title: "Sync booking late",
        attendee_message: nil,
        start_time: DateTime.add(early, 4, :hour)
      )

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Sync provider",
        start_at: DateTime.add(early, 2, :hour)
      )

      assert [%{summary: "Sync provider"}, %{summary: "Sync booking late"}] =
               CalendarGrid.search_events(user.id, "sync", [integration])

      assert [%{summary: "Sync provider"}] =
               CalendarGrid.search_events(user.id, "sync", [integration], limit: 1)
    end
  end
end
