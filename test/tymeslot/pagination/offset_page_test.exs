defmodule Tymeslot.Pagination.OffsetPageTest do
  use ExUnit.Case, async: true

  @moduletag :utils

  alias Tymeslot.Pagination.OffsetPage

  defp fetch(total, page, per_page) do
    OffsetPage.fetch(total, page, per_page, fn limit, offset -> {limit, offset} end)
  end

  describe "fetch/4" do
    test "loads the requested slice and counts the pages" do
      assert %OffsetPage{entries: {20, 20}, page: 2, per_page: 20, total: 45, total_pages: 3} =
               fetch(45, 2, 20)
    end

    test "clamps the page to the pages that exist" do
      assert %{page: 3, entries: {20, 40}} = fetch(45, 9, 20)
      assert %{page: 1, entries: {20, 0}} = fetch(45, 0, 20)
    end

    test "has one empty page when there are no rows" do
      assert %{page: 1, total_pages: 1, entries: {20, 0}} = fetch(0, 4, 20)
    end

    test "falls back to the default page size for an unsupported one" do
      assert %{per_page: 20} = fetch(45, 1, 7)
      assert %{per_page: 100, total_pages: 1} = fetch(45, 1, 100)
    end
  end

  describe "parse_page/1 and parse_per_page/1" do
    test "accept positive whole numbers and offered sizes only" do
      assert {:ok, 3} = OffsetPage.parse_page("3")
      assert :error = OffsetPage.parse_page("0")
      assert :error = OffsetPage.parse_page("2abc")
      assert :error = OffsetPage.parse_page(nil)

      assert {:ok, 50} = OffsetPage.parse_per_page("50")
      assert :error = OffsetPage.parse_per_page("1000")
    end
  end
end
