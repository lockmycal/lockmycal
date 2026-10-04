defmodule TymeslotWeb.Components.DashboardLayoutTest do
  # async: false — the footer tests set the global `:web_host` config.
  use TymeslotWeb.ConnCase, async: false

  @moduletag :utils

  import Phoenix.LiveViewTest
  import Phoenix.Component
  import Tymeslot.Factory
  alias Floki
  alias TymeslotWeb.Components.DashboardLayout
  alias TymeslotWeb.Live.Shared.DocsUrl

  test "renders dashboard layout with sidebar and top navigation" do
    assigns = %{}
    user = build(:user)
    profile = build(:profile, user: user, username: "testuser", full_name: "Test User")

    component_assigns = %{
      current_user: user,
      profile: profile,
      current_action: :overview,
      integration_status: %{has_calendar: true},
      inner_block: [
        %{__slot__: :inner_block, inner_block: fn _assigns, _changed -> ~H"Main Content" end}
      ]
    }

    html = render_component(&DashboardLayout.dashboard_layout/1, component_assigns)
    doc = Floki.parse_document!(html)

    assert html =~ "LockMyCal"
    assert html =~ "Test User"
    assert html =~ "Main Content"

    assert Floki.find(doc, "div#dashboard-root[phx-hook='ClipboardCopy']") != []
    assert Floki.find(doc, "aside#dashboard-sidebar") != []
    assert Floki.find(doc, "nav.brand-nav") != []
  end

  test "top_navigation renders correctly" do
    user = build(:user)
    profile = build(:profile, user: user, username: "testuser", full_name: "Test User")

    assigns = %{
      current_user: user,
      profile: profile
    }

    html = render_component(&DashboardLayout.top_navigation/1, assigns)
    doc = Floki.parse_document!(html)

    assert html =~ "LockMyCal"
    assert html =~ "Test User"

    assert Floki.find(doc, "button[aria-label='Toggle sidebar']") != []
  end

  test "top_navigation links to the docs, and to no website while WEB_HOST is unset" do
    user = build(:user)
    profile = build(:profile, user: user)

    html =
      render_component(&DashboardLayout.top_navigation/1, %{current_user: user, profile: profile})

    doc = Floki.parse_document!(html)

    assert [docs] = Floki.find(doc, "a[aria-label='Documentation']")
    assert Floki.attribute(docs, "href") == [DocsUrl.home_url()]
    assert Floki.attribute(docs, "target") == ["_blank"]
    assert Floki.find(doc, "a[aria-label='Website']") == []
  end

  describe "footer" do
    setup do
      previous = Application.fetch_env(:tymeslot, :web_host)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:tymeslot, :web_host, value)
          :error -> Application.delete_env(:tymeslot, :web_host)
        end
      end)
    end

    test "links to the website's bug forum once WEB_HOST is set" do
      Application.put_env(:tymeslot, :web_host, "https://example.com")
      doc = render_layout()

      assert [link] = Floki.find(doc, "footer a")
      assert Floki.attribute(link, "href") == ["https://example.com/forum/bugs"]
      assert Floki.attribute(link, "target") == ["_blank"]
      assert Floki.text(link) =~ "Report a bug"
    end

    test "shows the app name and version, without the bug link while WEB_HOST is unset" do
      Application.put_env(:tymeslot, :web_host, nil)
      assert [footer] = Floki.find(render_layout(), "footer")

      assert Floki.text(footer) =~ "Powered by LockMyCal · v#{Application.spec(:tymeslot, :vsn)}"
      assert Floki.find(footer, "a") == []
    end
  end

  defp render_layout do
    assigns = %{}
    user = build(:user)

    html =
      render_component(&DashboardLayout.dashboard_layout/1, %{
        current_user: user,
        profile: build(:profile, user: user),
        current_action: :overview,
        inner_block: [
          %{__slot__: :inner_block, inner_block: fn _assigns, _changed -> ~H"Main Content" end}
        ]
      })

    Floki.parse_document!(html)
  end
end
