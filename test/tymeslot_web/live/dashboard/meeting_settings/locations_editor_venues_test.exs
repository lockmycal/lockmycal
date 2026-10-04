defmodule TymeslotWeb.Dashboard.MeetingSettings.LocationsEditorVenuesTest do
  @moduledoc """
  The saved locations an in-person location offers in the meeting type form's
  Location tab: picking them, creating one without leaving the editor, and what
  happens to a location whose saved location is deleted meanwhile.
  """
  use TymeslotWeb.LiveCase, async: false

  @moduletag :integration
  @moduletag :meeting_types
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory
  import Tymeslot.LocationsEditorTestHelpers

  alias Tymeslot.MeetingTypes
  alias Tymeslot.MeetingTypes.LocationOption
  alias Tymeslot.Repo
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.Venues

  setup :setup_dashboard_user

  describe "an in-person location's saved locations" do
    test "names the saved location it offers in the list", %{user: user} = ctx do
      berlin =
        insert(:venue, user: user, name: "Berlin office", description: "Friedrichstrasse 1")

      {view, _type} = open_editor(ctx, [%{office() | venue_ids: [berlin.id]}])

      assert render(view) =~ "Berlin office (Friedrichstrasse 1)"
    end

    test "offers the organiser's saved locations and stores the ones ticked",
         %{user: user} = ctx do
      berlin = insert(:venue, user: user, name: "Berlin office")
      munich = insert(:venue, user: user, name: "Munich office")
      {view, meeting_type} = open_editor(ctx, [office()])

      view
      |> element("[phx-click='edit_location'][phx-value-id='loc-office']")
      |> render_click()

      offered =
        view
        |> element("#location_venue_ids")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("[data-testid='location_venue_ids-option']")
        |> Enum.map(&String.trim(Floki.text(&1)))

      assert offered == ["Berlin office", "Munich office"]

      view
      |> form("#location-editor-form", %{
        "location" => %{
          "kind" => "in_person",
          "label" => "Our offices",
          "venue_ids" => ["", to_string(berlin.id), to_string(munich.id)]
        }
      })
      |> render_submit()

      assert [offices] = reload(view, meeting_type, user).locations
      assert offices.venue_ids == [berlin.id, munich.id]
      assert offices.label == "Our offices"
    end

    test "a location that offered a deleted one does not stop the meeting type saving",
         %{user: user} = ctx do
      berlin = insert(:venue, user: user, name: "Berlin office")
      gone = insert(:venue, user: user, name: "Closed office")
      # Deleting through `Venues` would also rewrite the meeting type, so this
      # removes the row directly: it guards a mismatch between the library and
      # a location's ids, not a path the product takes.
      Repo.delete!(gone)

      {view, meeting_type} =
        open_editor(ctx, [
          %{office() | venue_ids: [gone.id, berlin.id]},
          %LocationOption{
            id: "loc-call",
            kind: "phone",
            label: "Ring us",
            details: "+44",
            position: 1
          }
        ])

      # Saving the other location saves the whole list, the office included.
      view
      |> element("[phx-click='edit_location'][phx-value-id='loc-call']")
      |> render_click()

      view
      |> form("#location-editor-form", %{"location" => %{"label" => "Call us"}})
      |> render_submit()

      assert [offices, call] = reload(view, meeting_type, user).locations
      assert call.label == "Call us"
      assert offices.venue_ids == [berlin.id]
    end

    test "an open form keeps saving after a location it offers is deleted elsewhere",
         %{user: user} = ctx do
      berlin = insert(:venue, user: user, name: "Berlin office")
      munich = insert(:venue, user: user, name: "Munich office")
      {view, meeting_type} = open_editor(ctx, [%{office() | venue_ids: [berlin.id, munich.id]}])

      # From the Locations page in another tab, while this form stays open.
      {:ok, _deleted} = Venues.delete_venue(berlin)

      change_duration(view, "45")

      reloaded = reload(view, meeting_type, user)
      assert reloaded.duration_minutes == 45
      assert [%{venue_ids: [munich_id]}] = reloaded.locations
      assert munich_id == munich.id
      assert has_element?(view, "span", "All changes saved")

      view |> element("[phx-click='switch_tab'][phx-value-tab='location']") |> render_click()
      assert has_element?(view, "[data-testid='location-row']", "Munich office")
      refute render(view) =~ "Berlin office"
    end

    test "an open form keeps saving after the only location it offers is deleted elsewhere",
         %{user: user} = ctx do
      berlin = insert(:venue, user: user, name: "Berlin office")
      {view, meeting_type} = open_editor(ctx, [%{office() | venue_ids: [berlin.id]}])

      {:ok, _deleted} = Venues.delete_venue(berlin)

      change_duration(view, "45")

      reloaded = reload(view, meeting_type, user)
      assert reloaded.duration_minutes == 45
      assert [%{venue_ids: []}] = reloaded.locations

      view |> element("[phx-click='switch_tab'][phx-value-tab='location']") |> render_click()
      assert has_element?(view, "[data-testid='location-row']", "Address arranged after booking")
    end

    test "creating a meeting type goes through after a location it offers is deleted elsewhere",
         %{conn: conn, user: user} do
      berlin = insert(:venue, user: user, name: "Berlin office")
      {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

      view |> element("button", "Add Meeting Type") |> render_click()
      # The default reminder's hidden inputs cannot be re-encoded by
      # `form/3`; see the creation test in `MeetingSettingsTest`.
      view |> element("button[aria-label='Remove reminder']") |> render_click()
      view |> element("[phx-click='edit_location']") |> render_click()

      view
      |> form("#location-editor-form", %{
        "location" => %{"venue_ids" => ["", to_string(berlin.id)]}
      })
      |> render_submit()

      _drain = :sys.get_state(view.pid)
      {:ok, _deleted} = Venues.delete_venue(berlin)

      view
      |> form("form[phx-submit='save_meeting_type']", %{
        "meeting_type" => %{"name" => "Site visit", "duration" => "20"}
      })
      |> render_submit()

      assert render(view) =~ "Meeting type created"

      assert [%{locations: [%{venue_ids: []}]}] =
               user.id
               |> MeetingTypes.get_all_meeting_types()
               |> Enum.filter(&(&1.name == "Site visit"))
    end

    test "says when no address is selected", %{user: user} = ctx do
      berlin = insert(:venue, user: user, name: "Berlin office")
      {view, _meeting_type} = open_editor(ctx, [office()])

      view
      |> element("[phx-click='edit_location'][phx-value-id='loc-office']")
      |> render_click()

      assert has_element?(
               view,
               "[data-testid='venue-hint']",
               "No address selected: bookers are told it will be arranged after booking."
             )

      view
      |> form("#location-editor-form", %{
        "location" => %{"venue_ids" => ["", to_string(berlin.id)]}
      })
      |> render_change()

      refute has_element?(view, "[data-testid='venue-hint']")
    end

    test "+ New location creates a location and selects it without leaving the form",
         %{user: user} = ctx do
      {view, meeting_type} = open_editor(ctx, [office()])

      view
      |> element("[phx-click='edit_location'][phx-value-id='loc-office']")
      |> render_click()

      view |> element("[data-testid='new-venue-toggle']") |> render_click()

      # Its required name leaves blank-name errors to the form, not the browser.
      assert has_element?(view, "#new-venue-form[novalidate] input[name='venue[name]'][required]")

      view
      |> form("#new-venue-form", %{
        "venue" => %{"name" => "Studio", "description" => "Canal Street 5"}
      })
      |> render_submit()

      _drain = :sys.get_state(view.pid)

      assert [studio] = Venues.list_venues(user.id)
      assert studio.description == "Canal Street 5"
      assert has_element?(view, "#location_venue_ids input[value='#{studio.id}'][checked]")
      assert has_element?(view, "#location-editor-form")
      refute has_element?(view, "#new-venue-form")

      view |> form("#location-editor-form") |> render_submit()

      assert [location] = reload(view, meeting_type, user).locations
      assert location.venue_ids == [studio.id]
      # The page's own venue list has the new one too, so it is named here.
      assert render(view) =~ "Studio (Canal Street 5)"
    end

    test "+ New location does not make later edits to the meeting type go unsaved",
         %{user: user} = ctx do
      {view, meeting_type} = open_editor(ctx, [office()])
      duration = ~s|input[name="meeting_type[duration]"]|

      view |> element("[phx-click='switch_tab'][phx-value-tab='details']") |> render_click()
      view |> element(duration) |> render_change(%{"meeting_type" => %{"duration" => "45"}})
      assert reload(view, meeting_type, user).duration_minutes == 45

      view |> element("[phx-click='switch_tab'][phx-value-tab='location']") |> render_click()

      view
      |> element("[phx-click='edit_location'][phx-value-id='loc-office']")
      |> render_click()

      view |> element("[data-testid='new-venue-toggle']") |> render_click()
      view |> form("#new-venue-form", %{"venue" => %{"name" => "Studio"}}) |> render_submit()
      _drain = :sys.get_state(view.pid)
      view |> element("button[phx-click='cancel']", "Cancel") |> render_click()

      # Back to the value the editor was opened with: the page reloaded when
      # the location was created, and must not have handed the form that
      # older version to save against.
      view |> element("[phx-click='switch_tab'][phx-value-tab='details']") |> render_click()
      view |> element(duration) |> render_change(%{"meeting_type" => %{"duration" => "30"}})

      assert reload(view, meeting_type, user).duration_minutes == 30
    end

    test "+ New location keeps the form open with the error for a name already used",
         %{user: user} = ctx do
      insert(:venue, user: user, name: "Studio")
      {view, _meeting_type} = open_editor(ctx, [office()])

      view
      |> element("[phx-click='edit_location'][phx-value-id='loc-office']")
      |> render_click()

      view |> element("[data-testid='new-venue-toggle']") |> render_click()

      html =
        view
        |> form("#new-venue-form", %{"venue" => %{"name" => "Studio"}})
        |> render_submit()

      assert html =~ "has already been taken"
      assert has_element?(view, "#new-venue-form")
      assert [_only] = Venues.list_venues(user.id)
    end

    test "+ New location is refused over the meeting-type write limit", %{user: user} = ctx do
      {view, _meeting_type} = open_editor(ctx, [office()])

      view
      |> element("[phx-click='edit_location'][phx-value-id='loc-office']")
      |> render_click()

      view |> element("[data-testid='new-venue-toggle']") |> render_click()

      message =
        Enum.find_value(
          Stream.repeatedly(fn -> RateLimiter.check_meeting_type_write_rate_limit(user.id) end),
          fn
            {:error, :rate_limited, message} -> message
            :ok -> nil
          end
        )

      view |> form("#new-venue-form", %{"venue" => %{"name" => "Studio"}}) |> render_submit()
      _drain = :sys.get_state(view.pid)

      assert Venues.list_venues(user.id) == []
      assert has_element?(view, "#new-venue-form")
      assert has_element?(view, "#app-flash-group-error", message)
    end
  end
end
