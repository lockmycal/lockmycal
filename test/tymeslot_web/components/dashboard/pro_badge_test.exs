defmodule TymeslotWeb.Components.Dashboard.ProBadgeTest do
  use ExUnit.Case, async: true

  @moduletag :components
  @moduletag :dashboard

  import Phoenix.LiveViewTest

  alias TymeslotWeb.Components.Dashboard.ProBadge

  test "says Pro by default" do
    html = render_component(&ProBadge.pro_badge/1, %{})

    assert html =~ ~r/>\s*Pro\s*</
  end

  test "shows a custom label instead" do
    html = render_component(&ProBadge.pro_badge/1, %{label: "Pro add-on"})

    assert html =~ "Pro add-on"
  end
end
