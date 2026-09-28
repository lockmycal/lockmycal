defmodule Tymeslot.Dashboard.Admin.UserColumnTest do
  use ExUnit.Case, async: true

  @moduletag :dashboard
  @moduletag :unit

  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Tymeslot.Dashboard.Admin.UserColumn

  defmodule RowOnlyColumn do
    @behaviour UserColumn

    @impl UserColumn
    def header, do: "Row only"

    @impl UserColumn
    def render(user) do
      assigns = %{user: user}
      ~H"<span>row:{@user.id}</span>"
    end
  end

  defmodule ViewerAwareColumn do
    @behaviour UserColumn

    @impl UserColumn
    def header, do: "Viewer aware"

    @impl UserColumn
    def render(user, viewer) do
      assigns = %{user: user, viewer: viewer}
      ~H"<span>row:{@user.id} viewer:{@viewer.id}</span>"
    end
  end

  defmodule PreloadingColumn do
    @behaviour UserColumn

    @impl UserColumn
    def header, do: "Preloading"

    @impl UserColumn
    def preload(users), do: Map.new(users, &{&1.id, "data-#{&1.id}"})

    @impl UserColumn
    def render(user, viewer, preloaded) do
      assigns = %{user: user, viewer: viewer, preloaded: preloaded}
      ~H"<span>row:{@user.id} viewer:{@viewer.id} data:{@preloaded}</span>"
    end
  end

  describe "preload_all/2" do
    test "calls preload/1 once per column that implements it, keyed by column" do
      users = [%{id: 1}, %{id: 3}]

      assert UserColumn.preload_all([RowOnlyColumn, PreloadingColumn, ViewerAwareColumn], users) ==
               %{PreloadingColumn => %{1 => "data-1", 3 => "data-3"}}
    end

    test "returns an empty map when no column implements preload/1" do
      assert UserColumn.preload_all([RowOnlyColumn], [%{id: 1}]) == %{}
    end
  end

  describe "render_cell/4" do
    test "passes the row's preloaded entry to a column that implements render/3" do
      preloaded = UserColumn.preload_all([PreloadingColumn], [%{id: 1}])

      html =
        rendered_to_string(
          UserColumn.render_cell(PreloadingColumn, %{id: 1}, %{id: 2}, preloaded)
        )

      assert html == "<span>row:1 viewer:2 data:data-1</span>"
    end

    test "passes nil to render/3 when the row has no preloaded entry" do
      html = rendered_to_string(UserColumn.render_cell(PreloadingColumn, %{id: 1}, %{id: 2}))

      assert html == "<span>row:1 viewer:2 data:</span>"
    end

    test "ignores preloaded data for a column that only implements render/2" do
      preloaded = %{ViewerAwareColumn => %{1 => "unused"}}

      html =
        rendered_to_string(
          UserColumn.render_cell(ViewerAwareColumn, %{id: 1}, %{id: 2}, preloaded)
        )

      assert html == "<span>row:1 viewer:2</span>"
    end
  end

  describe "render_cell/3" do
    test "calls render/1 for a column that only implements render/1" do
      html = rendered_to_string(UserColumn.render_cell(RowOnlyColumn, %{id: 1}, %{id: 2}))

      assert html == "<span>row:1</span>"
    end

    test "passes the viewer to a column that implements render/2" do
      html = rendered_to_string(UserColumn.render_cell(ViewerAwareColumn, %{id: 1}, %{id: 2}))

      assert html == "<span>row:1 viewer:2</span>"
    end
  end
end
