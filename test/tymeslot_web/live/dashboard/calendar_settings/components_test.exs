defmodule TymeslotWeb.Dashboard.CalendarSettings.ComponentsTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :utils
  @moduletag :calendar

  import Phoenix.LiveViewTest
  alias TymeslotWeb.Dashboard.CalendarSettings.Components

  describe "connected_calendars_section" do
    test "renders nothing when integrations list is empty" do
      assigns = %{
        integrations: [],
        myself: "target"
      }

      html = render_component(&Components.connected_calendars_section/1, assigns)
      assert html == ""
    end

    test "renders integrations when list is not empty" do
      integration = %{
        id: 1,
        name: "My Calendar",
        provider: "google",
        is_active: true,
        needs_reauth: false,
        calendar_list: [],
        calendar_paths: [],
        base_url: nil,
        is_primary: true,
        default_booking_calendar_id: nil,
        provider_account_email: nil
      }

      assigns = %{
        integrations: [integration],
        is_refreshing: false,
        myself: "target"
      }

      html = render_component(&Components.connected_calendars_section/1, assigns)
      assert html =~ "Active for Conflict Checking"
      assert html =~ "My Calendar"
    end

    test "shows the connect button when every calendar is paused" do
      assigns = %{
        integrations: [integration(1, false)],
        is_refreshing: false,
        myself: "target"
      }

      html = render_component(&Components.connected_calendars_section/1, assigns)
      assert html =~ "Paused Calendars"
      refute html =~ "Active for Conflict Checking"
      assert count_connect_buttons(html) == 1
    end

    test "shows the connect button only once when active and paused calendars exist" do
      assigns = %{
        integrations: [integration(1, true), integration(2, false)],
        is_refreshing: false,
        myself: "target"
      }

      html = render_component(&Components.connected_calendars_section/1, assigns)
      assert count_connect_buttons(html) == 1
    end
  end

  defp integration(id, is_active) do
    %{
      id: id,
      name: "Calendar #{id}",
      provider: "google",
      is_active: is_active,
      needs_reauth: false,
      calendar_list: [],
      calendar_paths: [],
      base_url: nil,
      is_primary: id == 1,
      default_booking_calendar_id: nil,
      provider_account_email: nil
    }
  end

  defp count_connect_buttons(html) do
    html |> String.split(~s(phx-click="show_picker")) |> length() |> Kernel.-(1)
  end

  describe "config_view" do
    test "renders config view for nextcloud" do
      assigns = %{
        selected_provider: :nextcloud,
        myself: "target",
        security_metadata: %{},
        form_errors: %{},
        form_values: %{},
        discovered_calendars: [],
        show_calendar_selection: false,
        discovery_credentials: %{},
        is_saving: false
      }

      html = render_component(&Components.config_view/1, assigns)
      assert html =~ "Nextcloud"
      assert html =~ "Server URL"
    end

    test "renders config view for baikal" do
      assigns = %{
        selected_provider: :baikal,
        myself: "target",
        security_metadata: %{},
        form_errors: %{},
        form_values: %{},
        discovered_calendars: [],
        show_calendar_selection: false,
        discovery_credentials: %{},
        is_saving: false
      }

      html = render_component(&Components.config_view/1, assigns)
      assert html =~ "Baikal"
      assert html =~ "PHP-based CalDAV/CardDAV server"
    end

    test "renders fallback for unknown provider" do
      assigns = %{
        selected_provider: :unknown,
        myself: "target",
        security_metadata: %{},
        form_errors: %{},
        form_values: %{},
        discovered_calendars: [],
        show_calendar_selection: false,
        discovery_credentials: %{},
        is_saving: false
      }

      html = render_component(&Components.config_view/1, assigns)
      assert html =~ "Configuration form not available"
    end
  end
end
