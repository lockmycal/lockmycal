defmodule Tymeslot.Agenda.ColoursTest do
  @moduledoc """
  The colour each agenda entry is painted in (`Entry.colour_class`): the same
  precedence as the calendar grid, so an appointment wears the same colour on
  the Overview as in the calendar.
  """

  use Tymeslot.DataCase, async: true
  @moduletag :calendar

  alias Tymeslot.Agenda
  alias Tymeslot.Integrations.Calendar.Appearance

  setup do
    {:ok, user: insert(:user), tomorrow: Date.add(Date.utc_today(), 1)}
  end

  describe "day_agenda/2 colours" do
    test "a booking without a picked colour gets the booking colour",
         %{user: user, tomorrow: tomorrow} do
      booking(user, at(tomorrow, ~T[12:00:00]), title: "Client call")

      assert find_entry(Agenda.day_agenda(user, "Etc/UTC"), "Client call").colour_class ==
               "bg-primary-600"
    end

    test "a synced event falls back to its integration's colour",
         %{user: user, tomorrow: tomorrow} do
      integration = insert(:calendar_integration, user: user, colour: "sage")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        summary: "Team sync",
        start_at: at(tomorrow, ~T[13:00:00]),
        end_at: at(tomorrow, ~T[14:00:00]),
        all_day: false
      )

      assert find_entry(Agenda.day_agenda(user, "Etc/UTC"), "Team sync").colour_class ==
               "bg-calendar-sage"
    end

    test "the colour chosen for the event's calendar wins over the integration's",
         %{user: user, tomorrow: tomorrow} do
      integration = insert(:calendar_integration, user: user, colour: "sage")
      {:ok, _appearance} = Appearance.set_colour(user.id, integration.id, "primary", "grape")

      insert(:provider_calendar_event,
        calendar_integration: integration,
        provider_calendar_id: "primary",
        summary: "Team sync",
        start_at: at(tomorrow, ~T[13:00:00]),
        end_at: at(tomorrow, ~T[14:00:00]),
        all_day: false
      )

      assert find_entry(Agenda.day_agenda(user, "Etc/UTC"), "Team sync").colour_class ==
               "bg-calendar-grape"
    end

    test "an integration with no colour of its own takes its rotation slot",
         %{user: user, tomorrow: tomorrow} do
      external_event(user, at(tomorrow, ~T[13:00:00]), summary: "Team sync")

      assert find_entry(Agenda.day_agenda(user, "Etc/UTC"), "Team sync").colour_class ==
               "bg-calendar-1"
    end
  end

  defp booking(user, start, opts) do
    insert(
      :meeting,
      [
        organizer_email: user.email,
        start_time: start,
        end_time: DateTime.add(start, 3600, :second),
        status: "confirmed",
        # Entries are found by title, which meeting information would replace.
        attendee_message: nil
      ] ++ opts
    )
  end

  defp external_event(user, start, opts) do
    insert(
      :provider_calendar_event,
      [
        calendar_integration: insert(:calendar_integration, user: user),
        start_at: start,
        end_at: DateTime.add(start, 3600, :second),
        all_day: false
      ] ++ opts
    )
  end

  defp find_entry(day, title) do
    [day.next | day.today ++ day.tomorrow]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&(&1.title == title))
  end

  defp at(date, time), do: DateTime.new!(date, time, "Etc/UTC")
end
