defmodule TymeslotWeb.Components.Dashboard.Pagination do
  @moduledoc """
  Numbered pagination bar for a dashboard table: a "21–40 of 574" summary, a
  rows-per-page select, and First / Previous / page numbers / Next / Last.

  Purely presentational: every page button fires `page_event` with
  `phx-value-page`, and the select fires `per_page_event` with
  `%{"<per_page_param>" => %{"per_page" => _}}`; the caller loads the page.
  Long page ranges show the first, the last and the pages around the
  current one, with an ellipsis for each gap.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  @around 2

  attr :id, :string, required: true
  attr :page, :integer, required: true, doc: "1-based current page"
  attr :total_pages, :integer, required: true
  attr :total, :integer, required: true, doc: "number of rows across all pages"
  attr :per_page, :integer, required: true
  attr :per_page_options, :list, required: true
  attr :page_event, :string, required: true
  attr :per_page_event, :string, required: true
  attr :per_page_param, :string, default: "paging", doc: "form name the per-page select posts as"
  attr :target, :any, default: nil
  attr :class, :string, default: nil

  @spec pagination(map()) :: Phoenix.LiveView.Rendered.t()
  def pagination(assigns) do
    assigns =
      assigns
      |> assign(:first_row, min((assigns.page - 1) * assigns.per_page + 1, assigns.total))
      |> assign(:last_row, min(assigns.page * assigns.per_page, assigns.total))
      |> assign(:items, page_items(assigns.page, assigns.total_pages))

    ~H"""
    <div id={@id} class={["flex flex-wrap items-center justify-between gap-4", @class]}>
      <div class="flex flex-wrap items-center gap-4">
        <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
          {dgettext("dashboard_common", "%{first}–%{last} of %{total}",
            first: @first_row,
            last: @last_row,
            total: @total
          )}
        </p>

        <.form
          for={%{}}
          id={"#{@id}-per-page-form"}
          phx-change={@per_page_event}
          phx-target={@target}
          class="flex items-center gap-2"
        >
          <label
            for={"#{@id}-per-page"}
            class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200 whitespace-nowrap"
          >
            {dgettext("dashboard_common", "Rows per page")}
          </label>
          <.input
            type="select"
            id={"#{@id}-per-page"}
            name={"#{@per_page_param}[per_page]"}
            value={@per_page}
            options={@per_page_options}
          />
        </.form>
      </div>

      <nav
        :if={@total_pages > 1}
        aria-label={dgettext("dashboard_common", "Pagination")}
        class="flex items-center gap-1"
      >
        <.nav_button
          page={1}
          disabled={@page == 1}
          icon="hero-chevron-double-left-mini"
          label={dgettext("dashboard_common", "First page")}
          event={@page_event}
          target={@target}
        />
        <.nav_button
          page={@page - 1}
          disabled={@page == 1}
          icon="hero-chevron-left-mini"
          label={dgettext("dashboard_common", "Previous page")}
          event={@page_event}
          target={@target}
        />

        <%= for item <- @items do %>
          <span
            :if={item == :gap}
            class="px-1 text-token-sm text-neutral-400 dark:text-twilight-indigo-300"
          >
            …
          </span>
          <button
            :if={item != :gap}
            type="button"
            phx-click={@page_event}
            phx-value-page={item}
            phx-target={@target}
            disabled={item == @page}
            aria-current={if(item == @page, do: "page")}
            class={[
              "h-9 min-w-9 px-2 rounded-token-lg text-token-sm font-bold transition-colors",
              if(item == @page,
                do: "bg-primary-600 text-white cursor-default",
                else:
                  "text-neutral-700 dark:text-neutral-100 hover:bg-neutral-100 dark:hover:bg-twilight-indigo-800 cursor-pointer"
              )
            ]}
          >
            {item}
          </button>
        <% end %>

        <.nav_button
          page={@page + 1}
          disabled={@page == @total_pages}
          icon="hero-chevron-right-mini"
          label={dgettext("dashboard_common", "Next page")}
          event={@page_event}
          target={@target}
        />
        <.nav_button
          page={@total_pages}
          disabled={@page == @total_pages}
          icon="hero-chevron-double-right-mini"
          label={dgettext("dashboard_common", "Last page")}
          event={@page_event}
          target={@target}
        />
      </nav>
    </div>
    """
  end

  attr :page, :integer, required: true
  attr :disabled, :boolean, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :event, :string, required: true
  attr :target, :any, required: true

  defp nav_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-page={@page}
      phx-target={@target}
      disabled={@disabled}
      aria-label={@label}
      title={@label}
      class="row-action-button row-action-button--icon-only row-action-button--neutral"
    >
      <.icon name={@icon} class="w-4 h-4" />
    </button>
    """
  end

  @doc """
  The page numbers to show, with `:gap` where a run is left out: always the
  first and last page and the #{@around} pages either side of the current
  one. A gap of a single page shows that page instead.
  """
  @spec page_items(pos_integer(), pos_integer()) :: [pos_integer() | :gap]
  def page_items(page, total_pages) do
    [1, total_pages | Enum.to_list((page - @around)..(page + @around)//1)]
    |> Enum.filter(&(&1 >= 1 and &1 <= total_pages))
    |> Enum.uniq()
    |> Enum.sort()
    |> fill_gaps()
  end

  defp fill_gaps([first | rest]) do
    {items, _previous} =
      Enum.reduce(rest, {[first], first}, fn number, {acc, previous} ->
        case number - previous do
          1 -> {[number | acc], number}
          2 -> {[number, previous + 1 | acc], number}
          _gap -> {[number, :gap | acc], number}
        end
      end)

    Enum.reverse(items)
  end
end
