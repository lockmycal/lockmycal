defmodule TymeslotWeb.Components.DashboardSidebarTest do
  # async: false: :dashboard_extension_gettext is read wherever the sidebar renders, which is
  # every dashboard LiveView test.
  use TymeslotWeb.ConnCase, async: false

  @moduletag :utils

  import Phoenix.LiveViewTest
  alias Floki
  alias TymeslotWeb.Components.DashboardSidebar

  setup do
    on_exit(fn -> Gettext.put_locale(TymeslotWeb.Gettext, "en") end)
    :ok
  end

  test "renders sidebar with all navigation links" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    assert html =~ "Overview"
    assert html =~ "Availability"
    assert html =~ "Meeting Types"
    assert html =~ "Calendars"
    assert html =~ "Video"
    assert html =~ "Theme"
    assert html =~ "Meetings"
    assert html =~ "Calendar"
    # Payments defaults to hidden — `payments_allowed` isn't set here.
    refute html =~ "Payments"

    # Check exactly one active link, and it's the overview link
    active_links = Floki.find(doc, "a.dashboard-nav-link--active")
    assert length(active_links) == 1

    [active_link] = active_links
    assert Floki.attribute(active_link, "href") == ["/dashboard/overview"]
  end

  test "renders active link correctly for different actions" do
    # The Calendars item is current for its own action and for the legacy
    # `:integrations` action that redirects into it, so both highlight the
    # same link.
    action_to_path = %{
      overview: "/dashboard/overview",
      availability: "/dashboard/availability",
      meeting_settings: "/dashboard/meeting-settings",
      integrations: "/dashboard/calendar-integration",
      calendar_integration: "/dashboard/calendar-integration",
      video_integration: "/dashboard/video-integration",
      payments: "/dashboard/payments",
      theme: "/dashboard/theme",
      meetings: "/dashboard/meetings",
      calendar: "/dashboard"
    }

    for {action, expected_href} <- action_to_path do
      assigns = %{
        current_action: action,
        integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
        payments_allowed: true,
        profile: %{username: "testuser"}
      }

      html = render_component(&DashboardSidebar.sidebar/1, assigns)
      doc = Floki.parse_document!(html)

      active_links = Floki.find(doc, "a.dashboard-nav-link--active")
      assert length(active_links) == 1

      [active_link] = active_links
      assert Floki.attribute(active_link, "href") == [expected_href]
    end
  end

  test "shows scheduling link when allowed" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    # Scheduling page link
    assert Floki.find(
             doc,
             "a.dashboard-nav-link[href='/testuser'][target='_blank'][title='Open booking page']"
           ) != []

    # Copy link button is enabled
    copy_btn = Floki.find(doc, "button#copy-scheduling-link")
    assert length(copy_btn) == 1
    refute copy_btn |> List.first() |> Floki.attribute("disabled") |> Enum.any?()

    # Send-by-email button opens the shared dashboard modal
    email_btn = Floki.find(doc, "button#email-scheduling-link")
    assert length(email_btn) == 1
    assert email_btn |> Floki.attribute("phx-click") |> List.first() =~ "#share-links-modal"
  end

  test "disables scheduling link when no username" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true},
      profile: %{username: nil}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    assert html =~ "cursor-not-allowed"
    assert html =~ "Set a username in Settings to enable this feature"

    # No clickable scheduling link
    assert Floki.find(doc, "a[href='/testuser']") == []

    # Open, copy and email buttons all disabled with the same tooltip
    disabled_btns = Floki.find(doc, "button[disabled][title]")
    assert length(disabled_btns) == 3
    assert Floki.find(doc, "button#email-scheduling-link") == []

    assert Enum.all?(
             Floki.attribute(disabled_btns, "title"),
             &(&1 =~ "Set a username in Settings to enable this feature")
           )
  end

  test "disables scheduling link when no calendar connected" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: false},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    assert html =~ "cursor-not-allowed"
    assert html =~ "Connect a calendar in Calendar settings to enable this feature"

    # No clickable scheduling link
    assert Floki.find(doc, "a[href='/testuser']") == []

    # Open, copy and email buttons all disabled with the same tooltip
    disabled_btns = Floki.find(doc, "button[disabled][title]")
    assert length(disabled_btns) == 3
    assert Floki.find(doc, "button#email-scheduling-link") == []

    assert Enum.all?(
             Floki.attribute(disabled_btns, "title"),
             &(&1 =~ "Connect a calendar in Calendar settings to enable this feature")
           )
  end

  test "shows notification badges when setup is incomplete" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: false, has_video: false, has_meeting_types: false},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    # Exactly 3 notification badges now: meeting settings, Calendars and Video
    # each carry their own badge instead of one merged Integrations badge.
    assert length(
             Floki.find(doc, "a[href='/dashboard/meeting-settings'] .dashboard-nav-notification")
           ) == 1

    assert length(
             Floki.find(
               doc,
               "a[href='/dashboard/calendar-integration'] .dashboard-nav-notification"
             )
           ) == 1

    assert length(
             Floki.find(doc, "a[href='/dashboard/video-integration'] .dashboard-nav-notification")
           ) == 1

    assert length(Floki.find(doc, ".dashboard-nav-notification")) == 3
    assert html =~ "!"
  end

  test "Video badge shows when only video is unconnected" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: false, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    doc =
      (&DashboardSidebar.sidebar/1)
      |> render_component(assigns)
      |> Floki.parse_document!()

    assert length(
             Floki.find(doc, "a[href='/dashboard/video-integration'] .dashboard-nav-notification")
           ) == 1

    assert Floki.find(
             doc,
             "a[href='/dashboard/calendar-integration'] .dashboard-nav-notification"
           ) == []
  end

  test "Calendars badge shows when only calendar is unconnected" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: false, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    doc =
      (&DashboardSidebar.sidebar/1)
      |> render_component(assigns)
      |> Floki.parse_document!()

    assert length(
             Floki.find(
               doc,
               "a[href='/dashboard/calendar-integration'] .dashboard-nav-notification"
             )
           ) == 1

    assert Floki.find(doc, "a[href='/dashboard/video-integration'] .dashboard-nav-notification") ==
             []
  end

  test "Calendars and Video badges are absent once both are connected" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    doc =
      (&DashboardSidebar.sidebar/1)
      |> render_component(assigns)
      |> Floki.parse_document!()

    assert Floki.find(
             doc,
             "a[href='/dashboard/calendar-integration'] .dashboard-nav-notification"
           ) == []

    assert Floki.find(doc, "a[href='/dashboard/video-integration'] .dashboard-nav-notification") ==
             []
  end

  test "Payments link is hidden when payments are not allowed" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      payments_allowed: false,
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    assert Floki.find(doc, "a[href='/dashboard/payments']") == []
  end

  test "Payments link is shown when payments are allowed" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      payments_allowed: true,
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    assert [payments_link] = Floki.find(doc, "a[href='/dashboard/payments']")
    assert Floki.text(payments_link) =~ "Payments"
  end

  test "translates sidebar extension labels through the configured gettext backend" do
    pin_extension_gettext({TymeslotWeb.Gettext, "dashboard_common"})

    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"},
      sidebar_extensions: [
        %{
          id: :calendar_sync,
          label: "Calendar",
          icon: "hero-calendar-days",
          path: "/dashboard/calendar-sync",
          action: :calendar_sync
        }
      ]
    }

    Gettext.put_locale(TymeslotWeb.Gettext, "de")

    doc =
      (&DashboardSidebar.sidebar/1)
      |> render_component(assigns)
      |> Floki.parse_document!()

    assert doc |> Floki.find("a[href='/dashboard/calendar-sync']") |> Floki.text() =~ "Kalender"
  end

  test "falls back to the raw label when an extension has no matching translation" do
    pin_extension_gettext({TymeslotWeb.Gettext, "dashboard_common"})

    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"},
      sidebar_extensions: [
        %{
          id: :unregistered,
          label: "Some Untranslated Extension",
          icon: "hero-puzzle-piece",
          path: "/dashboard/unregistered",
          action: :unregistered
        }
      ]
    }

    Gettext.put_locale(TymeslotWeb.Gettext, "de")
    html = render_component(&DashboardSidebar.sidebar/1, assigns)

    assert html =~ "Some Untranslated Extension"
  end

  # In the umbrella build the SaaS config repoints :dashboard_extension_gettext at
  # its own catalogue, so these tests pin the Core default to stay deterministic
  # in both the standalone and umbrella test runs.
  defp pin_extension_gettext(backend_and_domain) do
    original = Application.fetch_env!(:tymeslot, :dashboard_extension_gettext)
    Application.put_env(:tymeslot, :dashboard_extension_gettext, backend_and_domain)
    on_exit(fn -> Application.put_env(:tymeslot, :dashboard_extension_gettext, original) end)
  end

  test "Administration section is hidden for non-admin (or anonymous) users" do
    assigns = %{
      current_action: :overview,
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    refute html =~ "Administration"
    assert Floki.find(doc, "a[href='/dashboard/admin']") == []

    html_with_regular_user =
      render_component(
        &DashboardSidebar.sidebar/1,
        Map.put(assigns, :current_user, %{is_admin: false})
      )

    refute html_with_regular_user =~ "Administration"
  end

  test "Administration section is hidden from an admin when the admin UI is disabled" do
    original = Application.get_env(:tymeslot, :enable_admin_ui)
    Application.put_env(:tymeslot, :enable_admin_ui, false)
    on_exit(fn -> Application.put_env(:tymeslot, :enable_admin_ui, original) end)

    assigns = %{
      current_action: :overview,
      current_user: %{is_admin: true},
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)

    # The route redirects when the admin UI is off, so the sidebar entry
    # must not dangle as a dead end.
    refute html =~ "Administration"
  end

  test "Administration section shows a Settings link to /admin for admin users" do
    assigns = %{
      current_action: :overview,
      current_user: %{is_admin: true},
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    assert html =~ "Administration"
    assert [settings_link] = Floki.find(doc, "a[href='/dashboard/admin']")
    assert Floki.text(settings_link) =~ "Settings"
  end

  test "Administration section shows a Users link to /dashboard/admin/users for admin users" do
    assigns = %{
      current_action: :overview,
      current_user: %{is_admin: true},
      integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
      profile: %{username: "testuser"}
    }

    html = render_component(&DashboardSidebar.sidebar/1, assigns)
    doc = Floki.parse_document!(html)

    assert [users_link] = Floki.find(doc, "a[href='/dashboard/admin/users']")
    assert Floki.text(users_link) =~ "Users"
  end

  test "App Settings and Users each highlight only their own link" do
    for {action, href} <- [admin: "/dashboard/admin", admin_users: "/dashboard/admin/users"] do
      assigns = %{
        current_action: action,
        current_user: %{is_admin: true},
        integration_status: %{has_calendar: true, has_video: true, has_meeting_types: true},
        profile: %{username: "testuser"}
      }

      doc =
        (&DashboardSidebar.sidebar/1)
        |> render_component(assigns)
        |> Floki.parse_document!()

      assert [active_link] = Floki.find(doc, "a[href='#{href}']")
      active_classes = active_link |> Floki.attribute("class") |> List.first() |> String.split()
      assert "dashboard-nav-link--active" in active_classes

      other_href =
        if href == "/dashboard/admin", do: "/dashboard/admin/users", else: "/dashboard/admin"

      assert [other_link] = Floki.find(doc, "a[href='#{other_href}']")
      other_classes = other_link |> Floki.attribute("class") |> List.first() |> String.split()
      refute "dashboard-nav-link--active" in other_classes
    end
  end

  describe "source code link" do
    setup do
      previous = Application.fetch_env(:tymeslot, :source_code_url)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:tymeslot, :source_code_url, value)
          :error -> Application.delete_env(:tymeslot, :source_code_url)
        end
      end)
    end

    test "links to the configured source code repository" do
      Application.put_env(:tymeslot, :source_code_url, "https://git.example.com/me/fork")

      doc =
        (&DashboardSidebar.sidebar/1)
        |> render_component(%{current_action: :overview, profile: %{username: "testuser"}})
        |> Floki.parse_document!()

      assert [link] = Floki.find(doc, "a#dashboard-source-code-link")
      assert Floki.attribute(link, "href") == ["https://git.example.com/me/fork"]
      assert Floki.attribute(link, "target") == ["_blank"]
      assert Floki.text(link) =~ "Source code"
    end
  end
end
