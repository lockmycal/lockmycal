defmodule Tymeslot.Pagination.OffsetPage do
  @moduledoc """
  One numbered page of a list, for dashboard tables paged with
  `TymeslotWeb.Components.Dashboard.Pagination`: the rows plus what the
  pagination bar needs (current page, page size, total rows and pages).

  Every paged table offers the same page sizes (`page_sizes/0`) and starts
  at `default_page_size/0`. `fetch/4` clamps the requested page to the
  pages that exist, so a page emptied since it was opened (a deletion, a
  narrower search) shows the last one instead of nothing.

  Offset-based, so meant for lists small enough to count on every load (an
  organizer's contacts, an install's users, a retention-bounded log);
  `Tymeslot.Pagination.CursorPage` is the keyset alternative.
  """

  @page_sizes [20, 50, 100]
  @default_page_size 20

  defstruct entries: [], page: 1, per_page: @default_page_size, total: 0, total_pages: 1

  @type t(entry) :: %__MODULE__{
          entries: [entry],
          page: pos_integer(),
          per_page: pos_integer(),
          total: non_neg_integer(),
          total_pages: pos_integer()
        }
  @type t :: t(term())

  @typedoc "Loads `limit` rows starting at `offset`."
  @type fetch_entries(entry) :: (pos_integer(), non_neg_integer() -> [entry])

  @doc "The page sizes a paged table offers."
  @spec page_sizes() :: [pos_integer()]
  def page_sizes, do: @page_sizes

  @doc "The page size a paged table starts with."
  @spec default_page_size() :: pos_integer()
  def default_page_size, do: @default_page_size

  @doc """
  Builds page `page` of `total` rows, loading its rows with
  `fetch_entries.(limit, offset)`. A `per_page` not in `page_sizes/0` falls
  back to `default_page_size/0`; `page` is clamped to `1..total_pages`.
  """
  @spec fetch(non_neg_integer(), integer(), integer(), fetch_entries(entry)) :: t(entry)
        when entry: term()
  def fetch(total, page, per_page, fetch_entries) do
    per_page = if per_page in @page_sizes, do: per_page, else: @default_page_size
    total_pages = max(div(total + per_page - 1, per_page), 1)
    page = page |> max(1) |> min(total_pages)

    %__MODULE__{
      entries: fetch_entries.(per_page, (page - 1) * per_page),
      page: page,
      per_page: per_page,
      total: total,
      total_pages: total_pages
    }
  end

  @doc "Parses a page number from a client event (`phx-value-page`)."
  @spec parse_page(term()) :: {:ok, pos_integer()} | :error
  def parse_page(value) when is_binary(value) do
    case Integer.parse(value) do
      {page, ""} when page > 0 -> {:ok, page}
      _invalid -> :error
    end
  end

  def parse_page(_value), do: :error

  @doc "Parses a page size from a client event; only `page_sizes/0` are accepted."
  @spec parse_per_page(term()) :: {:ok, pos_integer()} | :error
  def parse_per_page(value) do
    case parse_page(value) do
      {:ok, size} when size in @page_sizes -> {:ok, size}
      _invalid -> :error
    end
  end
end
