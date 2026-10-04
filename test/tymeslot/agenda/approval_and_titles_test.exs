defmodule Tymeslot.Agenda.ApprovalAndTitlesTest do
  @moduledoc """
  Bookings awaiting approval on the dashboard agenda (listed and marked red,
  never the hero) and how a booking entry is titled (`DisplayTitle`, per the
  organiser's `booking_title_source` preference).
  """

  use Tymeslot.DataCase, async: true
  @moduletag :calendar

  alias Tymeslot.Agenda
  alias Tymeslot.Agenda.Day
  alias Tymeslot.Agenda.Entry
  alias Tymeslot.CalendarGrid

  setup do
    {:ok, user: insert(:user), tomorrow: Date.add(Date.utc_today(), 1)}
  end

  describe "day_agenda/2 bookings awaiting approval" do
    test "lists a request on its day, marked and red, but never as the hero", %{
      user: user,
      tomorrow: tomorrow
    } do
      # The request starts first, so it would be the hero if requests qualified.
      booking(user, at(tomorrow, ~T[08:00:00]), title: "Request", status: "awaiting_approval")
      booking(user, at(tomorrow, ~T[10:00:00]), title: "Confirmed")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert %Entry{title: "Confirmed", awaiting_approval?: false} = day.next
      assert [%Entry{title: "Request"} = request] = day.tomorrow
      assert request.awaiting_approval?
      assert request.colour_class == "bg-red-600"
    end

    test "lists a booking awaiting approval once, in place of its synced hold", %{
      user: user,
      tomorrow: tomorrow
    } do
      slot = at(tomorrow, ~T[12:00:00])

      booking(user, slot,
        title: "Requested",
        status: "awaiting_approval",
        calendar_uid: "pending-1@tymeslot.com"
      )

      external_event(user, slot,
        summary: "Synced copy",
        uid: "pending-1@tymeslot.com",
        created_by_tymeslot: true
      )

      assert ["Requested"] = titles(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "drops the unstamped synced hold of a booking awaiting approval", %{
      user: user,
      tomorrow: tomorrow
    } do
      # A hold synced back from Google/Outlook need not carry the stamp; the
      # shared identifier still ties it to the pending booking.
      slot = at(tomorrow, ~T[16:30:00])

      booking(user, slot,
        title: "Requested",
        status: "awaiting_approval",
        provider_event_id: "google-hold"
      )

      external_event(user, slot,
        summary: "Held slot",
        provider_event_id: "google-hold",
        created_by_tymeslot: false
      )

      assert ["Requested"] = titles(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "leaves the hero empty when only requests are upcoming", %{
      user: user,
      tomorrow: tomorrow
    } do
      booking(user, at(tomorrow, ~T[08:00:00]), title: "Request", status: "awaiting_approval")

      day = Agenda.day_agenda(user, "Etc/UTC")

      assert day.next == nil
      assert ["Request"] = Enum.map(day.tomorrow, & &1.title)
    end
  end

  describe "day_agenda/2 booking titles" do
    test "titles a booking by its meeting information by default", %{
      user: user,
      tomorrow: tomorrow
    } do
      booking(user, at(tomorrow, ~T[08:00:00]),
        title: "Consultation with Jane",
        attendee_message: "\n  Kitchen remodel quote\nSecond line"
      )

      assert ["Kitchen remodel quote"] = titles(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "falls back to the booking's own title without meeting information", %{
      user: user,
      tomorrow: tomorrow
    } do
      booking(user, at(tomorrow, ~T[08:00:00]),
        title: "Consultation with Jane",
        attendee_message: "   "
      )

      assert ["Consultation with Jane"] = titles(Agenda.day_agenda(user, "Etc/UTC"))
    end

    test "titles by the meeting type when the organiser chose so", %{
      user: user,
      tomorrow: tomorrow
    } do
      {:ok, _prefs} =
        CalendarGrid.save_preferences(user.id, %{booking_title_source: "meeting_type"})

      booking(user, at(tomorrow, ~T[08:00:00]),
        title: "Consultation with Jane",
        attendee_message: "Kitchen remodel quote"
      )

      assert ["Consultation with Jane"] = titles(Agenda.day_agenda(user, "Etc/UTC"))
    end
  end

  # --- Helpers ---------------------------------------------------------------

  # No meeting information unless a test sets it, so an entry is titled by its
  # own title under the default title source.
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

  defp at(date, time), do: DateTime.new!(date, time, "Etc/UTC")

  defp titles(%Day{} = day),
    do: [day.next | day.today ++ day.tomorrow] |> Enum.reject(&is_nil/1) |> Enum.map(& &1.title)
end
