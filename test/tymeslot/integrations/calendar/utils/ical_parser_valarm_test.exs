defmodule Tymeslot.Integrations.Calendar.ICalParserValarmTest do
  use ExUnit.Case, async: true
  @moduletag :integrations

  alias Tymeslot.Integrations.Calendar.ICalNormaliser
  alias Tymeslot.Integrations.Calendar.ICalParser

  defp event_with(extra) do
    ~s"""
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:valarm@example.com
    DTSTART:20240315T100000Z
    DTEND:20240315T110000Z
    SUMMARY:Thunderbird event
    #{extra}
    END:VEVENT
    END:VCALENDAR
    """
  end

  describe "parse/1 with VALARM blocks" do
    test "reads the trigger and action of each alarm" do
      ical =
        event_with("""
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:-PT30M
        DESCRIPTION:Default Mozilla Description
        END:VALARM
        BEGIN:VALARM
        ACTION:EMAIL
        TRIGGER:-P1DT2H
        END:VALARM
        """)

      assert {:ok, [event]} = ICalParser.parse(ical)

      assert event.valarm == [
               %{trigger: "-PT30M", action: "DISPLAY"},
               %{trigger: "-P1DT2H", action: "EMAIL"}
             ]
    end

    test "the alarm's DESCRIPTION is not the event's description" do
      ical =
        event_with("""
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:-PT5M
        DESCRIPTION:Default Mozilla Description
        END:VALARM
        """)

      assert {:ok, [event]} = ICalParser.parse(ical)
      assert event.description == nil
    end

    test "an event without alarms has none" do
      assert {:ok, [event]} = ICalParser.parse(event_with("DESCRIPTION:Text"))
      assert event.valarm == []
      assert event.description == "Text"
    end
  end

  describe "normalised reminders" do
    defp reminders(extra) do
      {:ok, [event]} = ICalParser.parse(event_with(extra))

      {:ok, [normalised]} =
        ICalNormaliser.normalise_events(
          [event],
          %{
            calendar_integration_id: 1,
            provider_calendar_id: "cal",
            synced_at: ~U[2024-03-01 00:00:00Z]
          },
          :caldav
        )

      normalised.reminders
    end

    test "maps durations to minutes and keeps the action" do
      extra = """
      BEGIN:VALARM
      ACTION:DISPLAY
      TRIGGER:-PT30M
      END:VALARM
      BEGIN:VALARM
      ACTION:EMAIL
      TRIGGER:-P1DT2H
      END:VALARM
      BEGIN:VALARM
      ACTION:DISPLAY
      TRIGGER:PT0S
      END:VALARM
      """

      assert reminders(extra) == [
               %{method: :popup, minutes_before: 30},
               %{method: :email, minutes_before: 1560}
             ]
    end
  end
end
