defmodule Tymeslot.Integrations.Calendar.Runtime.BookingIntegrationResolverCalendarTest do
  @moduledoc """
  `BookingIntegrationResolver.resolve/1` given one calendar of an integration,
  as a booker's own copy of a meeting is written
  (`Tymeslot.Meetings.BookerCalendarSync`).
  """

  use Tymeslot.DataCase, async: true

  @moduletag :calendar
  @moduletag :integration

  import Tymeslot.Factory

  alias Tymeslot.Integrations.Calendar.Runtime.BookingIntegrationResolver

  describe "resolve({integration_id, user_id, calendar_id}) — one calendar of it" do
    test "targets that calendar instead of the connection's booking calendar" do
      user = insert(:user)
      insert(:profile, user: user)

      integration =
        insert(:calendar_integration,
          user: user,
          provider: "caldav",
          calendar_paths: ["/calendars/personal/", "/calendars/work/"],
          default_booking_calendar_id: "/calendars/personal/"
        )

      result = BookingIntegrationResolver.resolve({integration.id, user.id, "/calendars/work/"})

      assert result.id == integration.id
      assert result.default_booking_calendar_id == "/calendars/work/"
    end
  end
end
