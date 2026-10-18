defmodule Tymeslot.Integrations.Calendar.ICalParserQuotedParamTest do
  use ExUnit.Case, async: true
  @moduletag :integrations

  alias Tymeslot.Integrations.Calendar.ICalParser

  # Thunderbird writes `DESCRIPTION;ALTREP="data:text/html,…":plain text`. The
  # colon inside the quoted ALTREP is not the value separator (RFC 5545 §3.1).
  describe "parse/1 with a colon inside a quoted parameter value" do
    test "DESCRIPTION keeps only the text after the separator" do
      ical_content = ~s"""
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:altrep-description@example.com
      DTSTART:20240315T100000Z
      DTEND:20240315T110000Z
      SUMMARY:Thunderbird event
      DESCRIPTION;ALTREP="data:text/html,Tady%20je%20popis":Tady je popis
      END:VEVENT
      END:VCALENDAR
      """

      assert {:ok, [event]} = ICalParser.parse(ical_content)
      assert event.description == "Tady je popis"
    end

    test "a plain DESCRIPTION is unchanged" do
      ical_content = ~s"""
      BEGIN:VCALENDAR
      VERSION:2.0
      BEGIN:VEVENT
      UID:plain-description@example.com
      DTSTART;TZID=Europe/Prague:20240315T100000
      DTEND;TZID=Europe/Prague:20240315T110000
      DESCRIPTION:Text: with colon
      END:VEVENT
      END:VCALENDAR
      """

      assert {:ok, [event]} = ICalParser.parse(ical_content)
      assert event.description == "Text: with colon"
      assert event.start_time == ~U[2024-03-15 09:00:00Z]
    end
  end
end
