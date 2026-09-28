defmodule TymeslotWeb.Components.Dashboard.Integrations.ConnectionRowTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :utils

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias TymeslotWeb.Components.Dashboard.Integrations.Shared.ConnectionRow

  defp render_row(overrides) do
    assigns =
      Map.merge(
        %{
          id: "cal-1",
          icon: "google",
          icon_type: :calendar,
          title: "Google Calendar",
          type_tag: "CalDAV",
          summary: "Syncing 2 calendars",
          status: {:ok, "Healthy"},
          active?: true,
          toggle_event: "toggle_integration",
          myself: "hub"
        },
        overrides
      )

    render_component(
      fn assigns ->
        ~H"""
        <ConnectionRow.connection_row
          id={@id}
          icon={@icon}
          icon_type={@icon_type}
          title={@title}
          type_tag={@type_tag}
          summary={@summary}
          status={@status}
          active?={@active?}
          toggle_event={@toggle_event}
          myself={@myself}
        >
          <:actions>Actions slot content</:actions>
        </ConnectionRow.connection_row>
        """
      end,
      assigns
    )
  end

  describe "row content" do
    test "renders title, type tag, summary, and status label" do
      html = render_row(%{})

      assert html =~ "Google Calendar"
      assert html =~ "CalDAV"
      assert html =~ "Syncing 2 calendars"
      assert html =~ "Healthy"
    end

    test "renders the actions slot content always (no expand needed)" do
      html = render_row(%{})

      assert html =~ "Actions slot content"
    end

    test "has no expand/collapse chevron" do
      html = render_row(%{})

      refute html =~ ~s(phx-click="toggle_row")
      refute html =~ "hero-chevron-down"
      refute html =~ "hero-chevron-up"
    end

    test "omits the type tag when not given" do
      html = render_row(%{type_tag: nil})

      refute html =~ "CalDAV"
    end
  end

  describe "controls" do
    test "renders the status switch toggle for the row" do
      html = render_row(%{})

      assert html =~ ~s(id="toggle-cal-1")
      assert html =~ ~s(phx-click="toggle_integration")
    end

    test "de-emphasises the row when inactive" do
      html = render_row(%{active?: false})

      # Same active/inactive card border treatment as Meeting Types cards
      # (assets/css/components/cards.css) — .card-glass-unavailable.
      assert html =~ "card-glass-unavailable"
      refute html =~ "card-glass-available"
    end

    test "uses the active card border treatment when active" do
      html = render_row(%{active?: true})

      assert html =~ "card-glass-available"
      refute html =~ "card-glass-unavailable"
    end
  end
end
