defmodule TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.SharedCreateHelpersTest do
  @moduledoc """
  Unit tests for the create-event/ad-hoc-meeting validation and result
  helpers hoisted into `Shared` — previously duplicated, byte-for-byte, as
  private functions in both `CreateExecution` (calendar) and
  `BookingsManagement.QuickAddMeetingExecution` (Meetings page quick-add),
  since both submit the same reused create-event dialog.
  """

  use ExUnit.Case, async: true

  @moduletag :unit
  @moduletag :calendar

  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared

  describe "parse_date/1" do
    test "parses a valid ISO-8601 date" do
      assert {:ok, ~D[2026-04-10]} = Shared.parse_date("2026-04-10")
    end

    test "returns a translated error for an invalid date" do
      assert {:error, "Invalid date"} = Shared.parse_date("not-a-date")
    end
  end

  describe "to_utc_or_error/4" do
    test "converts a valid date/time to UTC" do
      assert {:ok, %DateTime{}} = Shared.to_utc_or_error(~D[2026-04-10], 10, 0, "Etc/UTC")
    end

    test "returns a translated error for an invalid timezone" do
      assert {:error, "Invalid time"} =
               Shared.to_utc_or_error(~D[2026-04-10], 10, 0, "Not/AZone")
    end
  end

  describe "authorize_optional_integration/2" do
    test "allows no integration selected" do
      assert :ok = Shared.authorize_optional_integration(%Phoenix.LiveView.Socket{}, nil)
    end
  end

  describe "validate_event_title/1" do
    test "accepts a title" do
      assert :ok = Shared.validate_event_title(%{title: "Standup"})
    end

    test "rejects a blank or missing title" do
      for title <- ["", "   ", nil] do
        assert {:error, "Event title is required"} = Shared.validate_event_title(%{title: title})
      end
    end
  end

  describe "validate_meeting_fields/2" do
    defp creating(overrides \\ %{}) do
      Map.merge(
        %{title: "Kickoff", guest_name: "Ada Lovelace", guest_email: "ada@example.com"},
        overrides
      )
    end

    test "accepts valid, distinct guest fields" do
      assert :ok = Shared.validate_meeting_fields(creating(), "organizer@example.com")
    end

    test "rejects a blank or missing meeting title" do
      for title <- ["", "   ", nil] do
        assert {:error, "Meeting title is required"} =
                 Shared.validate_meeting_fields(
                   creating(%{title: title}),
                   "organizer@example.com"
                 )
      end
    end

    test "rejects a blank guest name" do
      assert {:error, "Guest name is required"} =
               Shared.validate_meeting_fields(
                 creating(%{guest_name: "  "}),
                 "organizer@example.com"
               )
    end

    test "rejects an invalid guest email" do
      assert {:error, "A valid guest email is required"} =
               Shared.validate_meeting_fields(
                 creating(%{guest_email: "not-an-email"}),
                 "organizer@example.com"
               )
    end

    test "rejects the organizer's own email, case-insensitively" do
      assert {:error, "You cannot add yourself as a guest. Use a different email address."} =
               Shared.validate_meeting_fields(
                 creating(%{guest_email: "Organizer@Example.com"}),
                 "organizer@example.com"
               )
    end

    test "does not crash on a non-binary organizer email" do
      assert :ok = Shared.validate_meeting_fields(creating(), nil)
    end
  end

  describe "flash_for_create/1" do
    test "plain copy with no attendees" do
      assert Shared.flash_for_create([]) == "Event created."
    end

    test "attendees-invited copy when attendees are present" do
      assert Shared.flash_for_create([%{email: "a@x.com"}]) ==
               "Event created. Attendees have been invited."
    end
  end

  describe "base_creating/2" do
    defp socket_with_integrations(integrations) do
      %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, integrations: integrations}}
    end

    test "fills defaults and opens in meeting mode with no calendar connected" do
      creating = Shared.base_creating(socket_with_integrations([]), %{})

      assert creating.mode == :meeting
      assert creating.integration_id == nil
      assert creating.calendar_id == nil
      assert creating.title == ""
      assert creating.guest_name == ""
      assert creating.attendees == []
      assert creating.reminders == []
      assert creating.recurrence_rule == nil
    end

    test "opens in event mode when a calendar is connected" do
      creating =
        Shared.base_creating(
          socket_with_integrations([%{id: 1, provider: "caldav", calendar_list: []}]),
          %{}
        )

      assert creating.mode == :event
      assert creating.integration_id == 1
    end

    test "overrides win over the computed defaults" do
      creating =
        Shared.base_creating(socket_with_integrations([]), %{
          date: "2026-05-01",
          start_hour: 14,
          all_day: true
        })

      assert creating.date == "2026-05-01"
      assert creating.start_hour == 14
      assert creating.all_day
      # Untouched fields still get the regular default.
      assert creating.end_hour == 10
    end
  end
end
