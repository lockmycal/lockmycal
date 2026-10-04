defmodule Tymeslot.Integrations.Calendar.CalendarEventBuilderTitleTest do
  @moduledoc """
  The event written to the organiser's calendar is titled by their "Meeting
  Titles" preference, like the dashboard, and its description still carries
  everything the title leaves out.
  """

  use Tymeslot.DataCase, async: true

  @moduletag :calendar
  @moduletag :integration

  import Tymeslot.Factory

  alias Tymeslot.Integrations.Calendar.CalendarEventBuilder
  alias Tymeslot.Integrations.CalendarManagement

  defp meeting(user, attrs \\ %{}) do
    Map.merge(
      %{
        uid: "abc-123",
        calendar_uid: "abc-123-cal",
        title: "Consultation with Alice",
        meeting_type: "Consultation",
        description: "",
        start_time: ~U[2026-05-01 10:00:00Z],
        end_time: ~U[2026-05-01 11:00:00Z],
        attendee_timezone: "Europe/Prague",
        meeting_url: nil,
        location: nil,
        organizer_user_id: user.id,
        organizer_name: "Bob",
        organizer_email: "bob@example.com",
        attendee_name: "Alice",
        attendee_email: "alice@example.com",
        attendee_phone: "+420 123 456 789",
        attendee_company: "Acme",
        attendee_message: "Budget review\nSecond line"
      },
      attrs
    )
  end

  test "defaults to the meeting information, like the dashboard" do
    user = insert(:user)

    assert CalendarEventBuilder.build_event_data(meeting(user)).summary == "Budget review"
  end

  test "uses the meeting type title when the organiser chose it" do
    user = insert(:user)

    {:ok, _prefs} =
      CalendarManagement.save_preferences(user.id, %{booking_title_source: "meeting_type"})

    assert CalendarEventBuilder.build_event_data(meeting(user)).summary ==
             "Consultation with Alice"
  end

  test "falls back to the meeting's own title without meeting information" do
    user = insert(:user)

    assert CalendarEventBuilder.build_event_data(meeting(user, %{attendee_message: nil})).summary ==
             "Consultation with Alice"
  end

  test "the description keeps the whole message, contact details and meeting type" do
    user = insert(:user)
    description = CalendarEventBuilder.build_event_data(meeting(user)).description

    assert description =~
             "Attendee: Alice <alice@example.com>\nPhone: +420 123 456 789\nCompany: Acme\nMeeting type: Consultation\n\n"

    assert description =~ "Message from attendee:\nBudget review\nSecond line"
  end
end
