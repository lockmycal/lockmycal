defmodule TymeslotWeb.Dashboard.CalendarGrid.Modals.CalendarPickerTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :components
  @moduletag :calendar

  import Phoenix.LiveViewTest

  alias Tymeslot.Integrations.Calendar.CalendarEntry
  alias TymeslotWeb.Dashboard.CalendarGrid.EditWorkflow
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.CalendarPicker

  @integration %{
    id: 1,
    provider: :google,
    name: "Work Calendar",
    default_booking_calendar_id: nil,
    calendar_list: [
      %CalendarEntry{
        id: "primary@gmail.com",
        selected: true,
        primary: true,
        name: "Primary"
      },
      %CalendarEntry{
        id: "meetings@gmail.com",
        selected: true,
        primary: false,
        name: "Meetings"
      }
    ]
  }

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        integrations: [@integration],
        integration_colors: %{1 => "bg-primary-500"},
        selected_integration_id: 1,
        selected_calendar_id: "primary@gmail.com",
        myself: %Phoenix.LiveComponent.CID{cid: 1},
        event_name: "update_calendar"
      },
      overrides
    )
  end

  defp find(html, selector), do: html |> Floki.parse_document!() |> Floki.find(selector)

  test "groups each connection's calendars under its name" do
    html = render_component(&CalendarPicker.calendar_picker/1, base_assigns())

    # Upper-cased as text: a native <optgroup> label takes no CSS.
    assert [_group] = find(html, ~s|optgroup[label="WORK CALENDAR"]|)
    assert [_option] = find(html, ~s|option[value="1:primary@gmail.com"]|)
    assert [_option] = find(html, ~s|option[value="1:meetings@gmail.com"]|)
  end

  test "selects the event's calendar and marks it with its connection's colour" do
    html = render_component(&CalendarPicker.calendar_picker/1, base_assigns())

    assert [_selected] = find(html, ~s|option[value="1:primary@gmail.com"][selected]|)
    assert html =~ "bg-primary-500"
  end

  test "sends the chosen calendar through the given event" do
    html = render_component(&CalendarPicker.calendar_picker/1, base_assigns())

    assert [_form] = find(html, ~s|form[phx-change="update_calendar"]|)
    assert [_select] = find(html, ~s|select[name="calendar_target"]|)
  end

  test "is not offered as a control when there is only one calendar to show" do
    integration = %{@integration | calendar_list: [hd(@integration.calendar_list)]}

    html =
      render_component(
        &CalendarPicker.calendar_picker/1,
        base_assigns(%{integrations: [integration]})
      )

    assert [_disabled] = find(html, "select[disabled]")
  end

  test "renders default calendar button when no calendar list" do
    integration = %{@integration | calendar_list: []}

    html =
      render_component(
        &CalendarPicker.calendar_picker/1,
        base_assigns(%{integrations: [integration], selected_calendar_id: nil})
      )

    assert html =~ "Default calendar"
    assert [_option] = find(html, ~s|option[value="1:"][selected]|)
  end

  test "highlights the calendar the resolver actually returns, not an unselected primary" do
    # Calendar A is the provider-primary but unselected (e.g. after
    # unticking it in "Manage calendars"); B is selected instead. The
    # highlighted chip must land on B, the same calendar
    # `EditWorkflow.default_calendar_id_for/1` resolves for the write path.
    integration = %{
      @integration
      | default_booking_calendar_id: nil,
        calendar_list: [
          %CalendarEntry{id: "cal-a", primary: true, selected: false, name: "A"},
          %CalendarEntry{id: "cal-b", primary: false, selected: true, name: "B"}
        ]
    }

    html =
      render_component(
        &CalendarPicker.calendar_picker/1,
        base_assigns(%{integrations: [integration], selected_calendar_id: nil})
      )

    resolved_id = EditWorkflow.default_calendar_id_for(integration)

    assert resolved_id == "cal-b"

    # Only B is offered (A is unselected, so writable_calendars excludes it)
    # and it is the one selected.
    assert find(html, ~s|option[value="1:cal-a"]|) == []
    assert [_selected] = find(html, ~s|option[value="1:cal-b"][selected]|)
  end

  test "renders multiple integrations" do
    second = %{
      id: 2,
      provider: :caldav,
      name: "Personal CalDAV",
      calendar_list: [%CalendarEntry{id: "personal", selected: true, name: "Personal"}]
    }

    html =
      render_component(
        &CalendarPicker.calendar_picker/1,
        base_assigns(%{integrations: [@integration, second]})
      )

    assert [_group] = find(html, ~s|optgroup[label="WORK CALENDAR"]|)
    assert [_group] = find(html, ~s|optgroup[label="PERSONAL CALDAV"]|)
  end

  describe "expand_target/1" do
    test "splits the value into the integration and calendar ids" do
      assert CalendarPicker.expand_target(%{"calendar_target" => "7:/cal/work/"}) ==
               %{
                 "calendar_target" => "7:/cal/work/",
                 "integration-id" => "7",
                 "calendar-id" => "/cal/work/"
               }
    end

    test "keeps a colon inside the calendar id" do
      assert %{"calendar-id" => "https://dav.example.com/cal/"} =
               CalendarPicker.expand_target(%{
                 "calendar_target" => "7:https://dav.example.com/cal/"
               })
    end

    test "leaves the calendar out for a connection's provider default" do
      params = CalendarPicker.expand_target(%{"calendar_target" => "7:"})

      assert params["integration-id"] == "7"
      refute Map.has_key?(params, "calendar-id")
    end

    test "returns params without a target unchanged" do
      params = %{"integration-id" => "7", "calendar-id" => "x"}
      assert CalendarPicker.expand_target(params) == params
    end
  end

  describe "derive_event_calendar_id/2" do
    test "returns nil when integration is nil" do
      assert CalendarPicker.derive_event_calendar_id(%{}, nil) == nil
    end

    test "derives the calendar a synced event was tagged with" do
      event = %{
        provider_metadata: %{"organizer" => %{"email" => "meetings@gmail.com"}},
        provider_event_id: "google-event-1",
        provider_calendar_id: "meetings@gmail.com"
      }

      assert CalendarPicker.derive_event_calendar_id(event, @integration) == "meetings@gmail.com"
    end

    test "derives a Google invitation's calendar, not the organiser's address" do
      # Someone else organised the meeting; it sits on the secondary calendar.
      event = %{
        provider_metadata: %{"organizer" => %{"email" => "someone@example.com"}},
        provider_event_id: "google-event-2",
        provider_calendar_id: "meetings@gmail.com"
      }

      assert CalendarPicker.derive_event_calendar_id(event, @integration) == "meetings@gmail.com"
    end

    test "derives an Outlook event's calendar despite the organiser's address shape" do
      integration = %{
        id: 3,
        provider: :outlook,
        default_booking_calendar_id: nil,
        calendar_list: [
          %CalendarEntry{id: "outlook-default", selected: true, primary: true, name: "Calendar"},
          %CalendarEntry{id: "outlook-team", selected: true, primary: false, name: "Team"}
        ]
      }

      event = %{
        provider_metadata: %{
          "organizer" => %{"emailAddress" => %{"address" => "me@example.com"}}
        },
        provider_event_id: "AAMkAG-event",
        provider_calendar_id: "outlook-team"
      }

      assert CalendarPicker.derive_event_calendar_id(event, integration) == "outlook-team"
    end

    test "derives a CalDAV event's collection even when it carries an organiser" do
      integration = %{
        id: 1,
        provider: :caldav,
        calendar_list: [
          %CalendarEntry{id: "/caldav/work/", path: "/caldav/work/", selected: true},
          %CalendarEntry{id: "/caldav/personal/", path: "/caldav/personal/", selected: true}
        ],
        default_booking_calendar_id: "/caldav/work/"
      }

      event = %{
        provider_metadata: %{"organizer" => %{"email" => "me@example.com"}},
        provider_event_id: "/caldav/personal/booking-123.ics",
        provider_calendar_id: "/caldav/work/"
      }

      assert CalendarPicker.derive_event_calendar_id(event, integration) == "/caldav/personal/"
    end

    test "derives CalDAV calendar ID from provider_event_id path" do
      integration = %{
        id: 1,
        calendar_list: [
          %CalendarEntry{id: "/caldav/personal/", path: "/caldav/personal/", selected: true}
        ],
        default_booking_calendar_id: nil
      }

      event = %{provider_metadata: nil, provider_event_id: "/caldav/personal/event-123.ics"}
      assert CalendarPicker.derive_event_calendar_id(event, integration) == "/caldav/personal/"
    end

    test "falls back to default when no match" do
      event = %{provider_metadata: nil, provider_event_id: nil}
      result = CalendarPicker.derive_event_calendar_id(event, @integration)

      assert result == "primary@gmail.com"
    end
  end
end
