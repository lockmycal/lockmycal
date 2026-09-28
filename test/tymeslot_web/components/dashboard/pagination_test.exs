defmodule TymeslotWeb.Components.Dashboard.PaginationTest do
  use ExUnit.Case, async: true

  @moduletag :components
  @moduletag :ui

  import Phoenix.LiveViewTest

  alias TymeslotWeb.Components.Dashboard.Pagination

  describe "page_items/2" do
    test "lists every page when there are few" do
      assert Pagination.page_items(1, 1) == [1]
      assert Pagination.page_items(3, 5) == [1, 2, 3, 4, 5]
    end

    test "keeps first, last and two pages either side, with gaps between" do
      assert Pagination.page_items(1, 20) == [1, 2, 3, :gap, 20]
      assert Pagination.page_items(10, 20) == [1, :gap, 8, 9, 10, 11, 12, :gap, 20]
      assert Pagination.page_items(20, 20) == [1, :gap, 18, 19, 20]
    end

    test "shows a single left-out page instead of a gap" do
      assert Pagination.page_items(5, 20) == [1, 2, 3, 4, 5, 6, 7, :gap, 20]
    end
  end

  describe "pagination/1" do
    defp render_pagination(overrides) do
      render_component(
        &Pagination.pagination/1,
        Map.merge(
          %{
            id: "pager",
            page: 2,
            total_pages: 3,
            total: 45,
            per_page: 20,
            per_page_options: [20, 50, 100],
            page_event: "page",
            per_page_event: "per_page"
          },
          overrides
        )
      )
    end

    test "summarises the rows shown and marks the current page" do
      html = render_pagination(%{})

      assert html =~ "21–40 of 45"
      assert html =~ ~s(aria-current="page")
      assert html =~ ~s(<option selected value="20">20</option>)
    end

    test "hides the page buttons when everything fits on one page" do
      html = render_pagination(%{page: 1, total_pages: 1, total: 5})

      assert html =~ "1–5 of 5"
      refute html =~ "phx-value-page"
    end
  end
end
