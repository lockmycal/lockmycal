defmodule TymeslotWeb.Dashboard.MeetingSettings.CardTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :components
  @moduletag :meeting_types

  import Phoenix.LiveViewTest

  alias Tymeslot.Availability.Schedules
  alias Tymeslot.CustomFields.FieldDefinition
  alias Tymeslot.Integrations.Calendar.CalendarEntry
  alias Tymeslot.MeetingTypes.LocationOption
  alias TymeslotWeb.Dashboard.MeetingSettings.Card

  defp build_type(overrides) do
    base = %{
      id: 1,
      name: "Strategy Call",
      description: nil,
      duration_minutes: 30,
      icon: "hero-bolt",
      is_active: true,
      is_private: false,
      allow_video: false,
      payment_required: false,
      price_cents: nil,
      custom_fields: [],
      video_integration: nil,
      calendar_integration: nil,
      target_calendar_id: nil,
      availability_schedule_id: nil,
      requires_approval: false,
      allow_attachments: false,
      max_bookings_per_day: nil,
      max_bookings_per_week: nil,
      max_bookings_per_month: nil,
      translations: []
    }

    Map.merge(base, overrides)
  end

  defp render_card(type, assigns \\ %{}) do
    render_component(
      &Card.meeting_type_card/1,
      Map.merge(%{type: type, myself: %Phoenix.LiveComponent.CID{cid: 1}}, assigns)
    )
  end

  describe "name and description" do
    setup do
      type =
        build_type(%{
          name: "Short consultation",
          description: "Quick and effective",
          translations: [
            %Tymeslot.MeetingTypes.MeetingTypeTranslation{
              locale: "cs",
              name: "Krátká konzultace",
              description: "Rychle a efektivně"
            }
          ]
        })

      %{type: type}
    end

    test "shows the host's translation for the dashboard's language", %{type: type} do
      # The locale is per process, so this doesn't leak into other tests.
      Gettext.put_locale(TymeslotWeb.Gettext, "cs")

      html = render_card(type)

      assert html =~ "Krátká konzultace"
      assert html =~ "Rychle a efektivně"
      refute html =~ "Short consultation"
    end

    test "falls back to the base text where there is no translation", %{type: type} do
      Gettext.put_locale(TymeslotWeb.Gettext, "de")

      html = render_card(type)

      assert html =~ "Short consultation"
      assert html =~ "Quick and effective"
    end
  end

  describe "paid token" do
    test "renders the formatted price for a paid meeting type" do
      html =
        render_card(build_type(%{payment_required: true, price_cents: 900}), %{currency: "eur"})

      assert html =~ "€9.00"
    end

    test "is omitted when the meeting type is free" do
      html = render_card(build_type(%{payment_required: false, price_cents: nil}))

      refute html =~ "€"
      refute html =~ "hero-banknotes-mini"
    end

    test "is omitted when payment is required but no price is set" do
      html = render_card(build_type(%{payment_required: true, price_cents: nil}))

      refute html =~ "hero-banknotes-mini"
    end
  end

  describe "description" do
    defp description_paragraphs(html) do
      html
      |> Floki.parse_fragment!()
      |> Floki.find("p")
    end

    defp description_text(html) do
      html |> description_paragraphs() |> Floki.text() |> String.trim()
    end

    test "renders the description below the title and above the duration" do
      html = render_card(build_type(%{description: "A quick chat about your roadmap."}))

      assert description_text(html) == "A quick chat about your roadmap."

      assert Regex.match?(
               ~r/Strategy Call.*A quick chat about your roadmap\..*30 min/s,
               Floki.text(Floki.parse_fragment!(html))
             )
    end

    test "escapes HTML in the description" do
      html = render_card(build_type(%{description: "<script>alert(1)</script>"}))

      refute html =~ "<script>"
      assert description_text(html) == "<script>alert(1)</script>"
    end

    test "is omitted when the meeting type has no description" do
      html = render_card(build_type(%{description: nil}))

      assert html =~ "Strategy Call"
      assert description_paragraphs(html) == []
    end

    test "is omitted when the description is only whitespace" do
      html = render_card(build_type(%{description: "   \n  "}))

      assert description_paragraphs(html) == []
    end
  end

  describe "custom questions token" do
    test "pluralises the count when there are multiple questions" do
      html = render_card(build_type(%{custom_fields: [%FieldDefinition{}, %FieldDefinition{}]}))

      assert html =~ "+2 custom questions"
    end

    test "uses the singular form for a single question" do
      html = render_card(build_type(%{custom_fields: [%FieldDefinition{}]}))

      assert html =~ "+1 custom question"
      refute html =~ "+1 custom questions"
    end

    test "is omitted when there are no custom questions" do
      html = render_card(build_type(%{custom_fields: []}))

      refute html =~ "custom question"
    end
  end

  describe "target calendar warning" do
    defp calendar_type(target_calendar_id, calendars) do
      build_type(%{
        target_calendar_id: target_calendar_id,
        calendar_integration: %{
          provider: "caldav",
          name: "Work account",
          calendar_list: Enum.map(calendars, &CalendarEntry.normalize/1)
        }
      })
    end

    test "flags a target calendar the host can no longer write to" do
      html =
        render_card(
          calendar_type("cal-2", [
            %{id: "cal-1", name: "Primary", selected: true, read_only: false},
            %{id: "cal-2", name: "Shared", selected: true, read_only: true}
          ])
        )

      assert html =~ "Read-only"
      assert html =~ "can no longer write to"
    end

    test "flags a target calendar that has left the account" do
      html =
        render_card(
          calendar_type("cal-gone", [
            %{id: "cal-1", name: "Primary", selected: true, read_only: false}
          ])
        )

      assert html =~ "Calendar gone"
      refute html =~ "Read-only"
    end

    test "is silent while the target calendar is still writable" do
      html =
        render_card(
          calendar_type("cal-1", [
            %{id: "cal-1", name: "Primary", selected: true, read_only: false},
            %{id: "cal-2", name: "Shared", selected: true, read_only: true}
          ])
        )

      refute html =~ "Read-only"
      refute html =~ "Calendar gone"
    end

    test "is silent when the integration's calendar list has never been populated" do
      html = render_card(calendar_type("cal-1", []))

      refute html =~ "Read-only"
      refute html =~ "Calendar gone"
    end
  end

  describe "availability schedule" do
    @schedules [
      %{id: 10, name: "Office hours", is_default: true},
      %{id: 11, name: "Evenings", is_default: false}
    ]

    test "names the default schedule for a type that follows it" do
      html = render_card(build_type(%{availability_schedule_id: nil}), %{schedules: @schedules})

      assert html =~ "Office hours"
      assert html =~ "Availability schedule: Office hours (default)"
    end

    test "names the schedule a type picked" do
      html = render_card(build_type(%{availability_schedule_id: 11}), %{schedules: @schedules})

      assert html =~ "Evenings"
      refute html =~ "Office hours"
    end

    test "falls back to the default schedule's name when no schedules are loaded" do
      html = render_card(build_type(%{}))

      assert html =~ Schedules.default_schedule_name()
    end
  end

  describe "booking limits" do
    test "lists only the caps that are set" do
      html = render_card(build_type(%{max_bookings_per_day: 2, max_bookings_per_month: 20}))

      assert html =~ "2/day · 20/month"
      refute html =~ "/week"
    end

    test "is omitted when the type has no caps" do
      refute render_card(build_type(%{})) =~ "Booking limits"
    end
  end

  describe "approval and attachments" do
    test "flags a type that requires approval" do
      assert render_card(build_type(%{requires_approval: true})) =~ "Requires approval"
      refute render_card(build_type(%{})) =~ "Requires approval"
    end

    test "flags a type that takes attachments" do
      assert render_card(build_type(%{allow_attachments: true})) =~ "Attachments"
      refute render_card(build_type(%{})) =~ "Attachments"
    end
  end

  describe "location summary for a single in-person location" do
    defp in_person(venue_ids),
      do: %LocationOption{
        id: "loc-office",
        kind: "in_person",
        label: "Our office",
        venue_ids: venue_ids,
        position: 0
      }

    defp venues,
      do: [
        %{id: 1, name: "Berlin office", description: "Friedrichstrasse 1"},
        %{id: 2, name: "Munich office", description: nil}
      ]

    test "names its one saved location" do
      html = render_card(build_type(%{locations: [in_person([1])]}), %{venues: venues()})

      assert html =~ "Berlin office"
      refute html =~ "Our office"
    end

    test "counts several saved locations" do
      html = render_card(build_type(%{locations: [in_person([1, 2])]}), %{venues: venues()})

      assert html =~ "2 locations"
    end

    test "falls back to the location's label with no saved location" do
      html = render_card(build_type(%{locations: [in_person([])]}), %{venues: venues()})

      assert html =~ "Our office"
    end

    test "ignores a saved location that is no longer in the library" do
      html = render_card(build_type(%{locations: [in_person([1, 99])]}), %{venues: venues()})

      assert html =~ "Berlin office"
      refute html =~ "2 locations"
    end

    test "falls back to the label when its only saved location was deleted" do
      html = render_card(build_type(%{locations: [in_person([99])]}), %{venues: venues()})

      assert html =~ "Our office"
    end
  end
end
