defmodule Tymeslot.Agenda.AttendingTest do
  @moduledoc """
  A booking the user made on someone else's page, on their own agenda: named
  from their side under their own "Name bookings by", a pending one waiting on the organiser, and listed once
  even when its copy has synced back from the user's own calendar
  (`Tymeslot.Meetings.BookerCalendar`).
  """

  use Tymeslot.DataCase, async: true
  @moduletag :calendar

  alias Tymeslot.Agenda
  alias Tymeslot.Agenda.Day
  alias Tymeslot.Agenda.Entry
  alias Tymeslot.Integrations.CalendarManagement

  setup do
    {:ok, user: insert(:user), tomorrow: Date.add(Date.utc_today(), 1)}
  end

  defp attended_booking(user, start, opts) do
    insert(
      :meeting,
      [
        organizer_email: "host@example.com",
        organizer_name: "Jana Host",
        attendee_email: user.email,
        attendee_name: "Me Myself",
        meeting_type: "Consultation",
        attendee_message: nil,
        start_time: start,
        end_time: DateTime.add(start, 3600, :second),
        booker_user_id: user.id
      ] ++ opts
    )
  end

  defp at(date, time), do: DateTime.new!(date, time, "Etc/UTC")

  defp entries(%Day{} = day),
    do: Enum.reject([day.next | day.today ++ day.tomorrow], &is_nil/1)

  test "names the organiser, not the user, on a booking they made elsewhere", %{
    user: user,
    tomorrow: tomorrow
  } do
    attended_booking(user, at(tomorrow, ~T[10:00:00]),
      attendee_video_url: "https://video.example.com/attendee",
      organizer_video_url: "https://video.example.com/host"
    )

    assert [%Entry{} = entry] = entries(Agenda.day_agenda(user, "Etc/UTC"))
    assert entry.attending?
    assert entry.title == "Consultation with Jana Host"
    assert entry.who == "Jana Host"
    assert entry.join_url == "https://video.example.com/attendee"
  end

  test "is named by the meeting information the user typed, under their own preference", %{
    user: user,
    tomorrow: tomorrow
  } do
    attended_booking(user, at(tomorrow, ~T[10:00:00]), attendee_message: "Contract review")

    assert [%Entry{title: "Contract review"}] = entries(Agenda.day_agenda(user, "Etc/UTC"))

    {:ok, _preferences} =
      CalendarManagement.save_preferences(user.id, %{booking_title_source: "meeting_type"})

    assert [%Entry{title: "Consultation with Jana Host"}] =
             entries(Agenda.day_agenda(user, "Etc/UTC"))
  end

  test "a request the user sent waits on the organiser's approval", %{
    user: user,
    tomorrow: tomorrow
  } do
    attended_booking(user, at(tomorrow, ~T[10:00:00]), status: "awaiting_approval")

    assert [%Entry{awaiting_approval?: true, attending?: true}] =
             entries(Agenda.day_agenda(user, "Etc/UTC"))
  end

  test "lists the booking once although its copy synced back from the user's calendar", %{
    user: user,
    tomorrow: tomorrow
  } do
    integration = insert(:calendar_integration, user: user)
    start = at(tomorrow, ~T[10:00:00])

    meeting =
      attended_booking(user, start,
        booker_calendar_integration_id: integration.id,
        booker_calendar_event_id: "copy-uid-booker"
      )

    insert(:provider_calendar_event,
      calendar_integration: integration,
      uid: meeting.booker_calendar_event_id,
      summary: "Consultation with Jana Host",
      start_at: start,
      end_at: DateTime.add(start, 3600, :second),
      all_day: false
    )

    assert [%Entry{source: :tymeslot}] = entries(Agenda.day_agenda(user, "Etc/UTC"))
  end

  test "the user's own bookings are unchanged", %{user: user, tomorrow: tomorrow} do
    insert(:meeting,
      organizer_email: user.email,
      attendee_name: "Client",
      attendee_message: nil,
      title: "Client call",
      start_time: at(tomorrow, ~T[10:00:00]),
      end_time: at(tomorrow, ~T[11:00:00])
    )

    assert [%Entry{attending?: false, who: "Client"}] =
             entries(Agenda.day_agenda(user, "Etc/UTC"))
  end
end
