defmodule TymeslotWeb.Dashboard.CalendarGrid.Header do
  @moduledoc "Header toolbar function component for the calendar grid."

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Dashboard.Availability.Helpers, as: AvailabilityHelpers
  alias TymeslotWeb.Dashboard.CalendarGrid.Header.CalendarListPanel
  alias TymeslotWeb.Dashboard.CalendarGrid.Header.SearchBox
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers
  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.MiniMonthPopover

  attr :view, :atom, required: true
  attr :date, :any, required: true
  attr :integrations, :list, required: true
  attr :integration_colors, :map, required: true
  attr :hidden_integration_ids, :list, required: true
  attr :hidden_calendar_keys, :any, required: true
  attr :show_calendar_list, :boolean, required: true
  attr :show_view_menu, :boolean, required: true
  attr :mini_month_open, :boolean, default: false
  attr :mini_month_cursor, :any, default: nil
  attr :syncing, :boolean, required: true
  attr :timezone_display, :string, required: true
  attr :timezone_country_code, :atom
  attr :preferences, :any
  attr :search_term, :string, default: ""
  attr :search_results, :list, default: []
  attr :search_open, :boolean, default: false
  attr :user_timezone, :string, default: "Etc/UTC"
  attr :most_recent_sync_at, :any, default: nil
  attr :myself, :any, required: true

  @spec toolbar(map()) :: Phoenix.LiveView.Rendered.t()
  def toolbar(assigns) do
    ~H"""
    <div
      id="calendar-grid-header"
      class="border-b border-neutral-200 bg-white sticky top-0 z-20 dark:border-twilight-indigo-800 dark:bg-twilight-indigo-950"
    >
      <%!--
        Two-row layout at every size. The full toolbar never fits on a single
        row at common laptop widths, so rather than collapse to one row on md+
        (which forced the view switcher to wrap onto its own detached line and
        looked scrambled), we keep two stable rows:
          Row 1: navigation + period title, with the view switcher pinned right.
          Row 2: search, quick-add, import, calendars, refresh and settings.
        flex-wrap on each row lets it reflow gracefully when space is tight.
      --%>
      <div class="flex flex-col gap-1 md:gap-2 px-3 py-2 md:px-4 md:py-3">
        <%!-- Row 1: navigation (left) + view switcher (right) --%>
        <div class="flex items-center gap-2 min-w-0">
          <.icon_button
            icon="hero-chevron-left"
            label={dgettext("dashboard_calendar", "Previous period")}
            phx-click="prev_period"
            phx-target={@myself}
          />
          <.icon_button
            icon="hero-chevron-right"
            label={dgettext("dashboard_calendar", "Next period")}
            phx-click="next_period"
            phx-target={@myself}
          />
          <.action_button
            variant={:secondary}
            size={:sm}
            phx-click={
              JS.push("today", target: @myself)
              |> JS.dispatch("calendar:scroll-to-current", to: "#calendar-drag-zone")
            }
          >
            {dgettext("dashboard_calendar", "Today")}
          </.action_button>
          <%!--
            min-w-0 lets the period title shrink and truncate with an ellipsis
            when the row is tight (a long week range on a phone); the dropdown
            root cannot take the class itself.
          --%>
          <div class="ml-1 md:ml-2 min-w-0">
            <MiniMonthPopover.mini_month_popover
              open={@mini_month_open}
              view={@view}
              date={@date}
              cursor={@mini_month_cursor}
              preferences={@preferences}
              user_timezone={@user_timezone}
              myself={@myself}
            />
          </div>
          <div class="hidden md:block ml-1 min-w-0">
            <AvailabilityHelpers.timezone_display
              timezone_display={@timezone_display}
              country_code={@timezone_country_code}
            />
          </div>

          <%!--
            Segmented view switcher pinned to the right of the navigation row on
            md+. On mobile the compact `view_menu` lives in the tools row below,
            so this slot collapses (no `ml-auto` element) and the navigation
            keeps its natural left-aligned width.
          --%>
          <div class="hidden md:block ml-auto pl-1 shrink-0">
            <.view_tabs view={@view} myself={@myself} />
          </div>
        </div>

        <%!--
          Row 2: tools. Use flex-wrap (not overflow-x-auto) so the toolbar
          reflows on narrow screens. overflow-x-auto forces overflow-y to compute
          to auto, which clips the dropdown panels (calendars, search) that
          extend below the row via `top-full`. Below sm the row does not wrap:
          the timezone label shrinks and truncates instead, so the row stays on
          one line at 390px whatever the width of the view menu's label
          ("Agenda" is wider than "Week").
        --%>
        <div class="flex flex-nowrap sm:flex-wrap items-center gap-1.5 sm:gap-2">
          <div class="md:hidden min-w-0">
            <AvailabilityHelpers.timezone_display
              timezone_display={@timezone_display}
              country_code={@timezone_country_code}
            />
          </div>
          <SearchBox.search_box
            search_term={@search_term}
            search_results={@search_results}
            search_open={@search_open}
            user_timezone={@user_timezone}
            preferences={@preferences}
            integration_colors={@integration_colors}
            myself={@myself}
          />
          <.quick_add myself={@myself} />
          <.import_button myself={@myself} />
          <.view_menu view={@view} show_view_menu={@show_view_menu} myself={@myself} />
          <.calendar_list_dropdown
            :if={@integrations != []}
            integrations={@integrations}
            integration_colors={@integration_colors}
            hidden_integration_ids={@hidden_integration_ids}
            hidden_calendar_keys={@hidden_calendar_keys}
            show_calendar_list={@show_calendar_list}
            myself={@myself}
          />
          <.refresh_button :if={@integrations != []} syncing={@syncing} myself={@myself} />
          <.icon_button
            icon="hero-question-mark-circle"
            label={dgettext("dashboard_calendar", "Keyboard shortcuts")}
            class="hidden! md:inline-flex!"
            phx-click="toggle_shortcuts_help"
            phx-target={@myself}
          />
          <.icon_button
            icon="hero-cog-6-tooth"
            label={dgettext("dashboard_calendar", "Calendar settings")}
            phx-click="toggle_settings"
            phx-target={@myself}
          />
          <.last_sync_indicator :if={@most_recent_sync_at} synced_at={@most_recent_sync_at} />
        </div>
      </div>
    </div>
    """
  end

  attr :integrations, :list, required: true
  attr :integration_colors, :map, required: true
  attr :hidden_integration_ids, :list, required: true
  attr :hidden_calendar_keys, :any, required: true
  attr :show_calendar_list, :boolean, required: true
  attr :myself, :any, required: true

  defp calendar_list_dropdown(assigns) do
    ~H"""
    <.dropdown
      id="calendar-list-dropdown"
      open={@show_calendar_list}
      on_toggle="toggle_calendar_list"
      on_close="close_calendar_list"
      target={@myself}
      role="dialog"
      panel_label={dgettext("dashboard_calendar", "My Calendars")}
      trigger_class={Enum.join(button_classes(:secondary, :sm), " ")}
      class="bg-white border border-neutral-200 rounded-token-xl shadow-lg p-3 w-60 dark:bg-twilight-indigo-950 dark:border-twilight-indigo-800"
      aria-label={dgettext("dashboard_calendar", "Toggle calendars")}
    >
      <:trigger>
        <.icon name="hero-bars-3" class="w-4 h-4" />
        <span class="hidden md:inline">{dgettext("dashboard_calendar", "Calendars")}</span>
      </:trigger>
      <:panel>
        <CalendarListPanel.calendar_list_panel
          integrations={@integrations}
          integration_colors={@integration_colors}
          hidden_integration_ids={@hidden_integration_ids}
          hidden_calendar_keys={@hidden_calendar_keys}
          myself={@myself}
        />
      </:panel>
    </.dropdown>
    """
  end

  attr :view, :atom, required: true
  attr :show_view_menu, :boolean, required: true
  attr :myself, :any, required: true

  # Compact dropdown for the tools row on mobile (hidden on md+, where the
  # segmented `view_tabs` takes over on the navigation row).
  defp view_menu(assigns) do
    ~H"""
    <div class="md:hidden">
      <.dropdown
        id="view-switcher-dropdown"
        open={@show_view_menu}
        on_toggle="toggle_view_menu"
        on_close="close_view_menu"
        target={@myself}
        trigger_class={Enum.join(button_classes(:secondary, :sm), " ")}
        class="bg-white border border-neutral-200 rounded-token-xl shadow-lg py-1 w-36 dark:bg-twilight-indigo-950 dark:border-twilight-indigo-800"
        aria-label={dgettext("dashboard_calendar", "Switch view")}
      >
        <:trigger>
          <.icon name="hero-calendar-days" class="hidden sm:block w-4 h-4" />
          <span class="text-token-xs font-medium">{Helpers.view_label(@view)}</span>
          <.icon name="hero-chevron-down" class="w-3 h-3" />
        </:trigger>
        <:panel>
          <button
            :for={{value, label, icon} <- view_options()}
            phx-click="set_view"
            phx-value-view={Atom.to_string(value)}
            phx-target={@myself}
            class={"w-full flex items-center gap-2 text-left px-3 py-2 text-token-sm #{if @view == value, do: "bg-primary-50 dark:bg-primary-950/40 text-primary-700 dark:text-primary-300 font-semibold", else: "text-neutral-600 dark:text-neutral-300 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-900"}"}
          >
            <.icon name={icon} class="w-4 h-4 shrink-0" />
            <span>{label}</span>
          </button>
        </:panel>
      </.dropdown>
    </div>
    """
  end

  attr :view, :atom, required: true
  attr :myself, :any, required: true

  # Segmented button group pinned to the right of the navigation row on md+
  # (hidden on mobile, where the compact `view_menu` takes over).
  defp view_tabs(assigns) do
    ~H"""
    <.segmented_control
      id="calendar-view"
      value={@view}
      on_change="set_view"
      param="view"
      target={@myself}
      aria_label={dgettext("dashboard_calendar", "Switch view")}
    >
      <:option :for={{value, label, icon} <- view_options()} value={value} label={label} icon={icon} />
    </.segmented_control>
    """
  end

  defp view_options do
    [
      {:day, dgettext("dashboard_calendar", "Day"), "hero-view-columns"},
      {:three_day, dgettext("dashboard_calendar", "3 Days"), "hero-calendar"},
      {:week, dgettext("dashboard_calendar", "Week"), "hero-table-cells"},
      {:month, dgettext("dashboard_calendar", "Month"), "hero-squares-2x2"},
      {:agenda, dgettext("dashboard_calendar", "Agenda"), "hero-list-bullet"}
    ]
  end

  attr :myself, :any, required: true

  # Opens the create-event modal directly. The full draft is built and edited in
  # the modal itself, so there is no inline text entry to parse here.
  defp quick_add(assigns) do
    ~H"""
    <%!-- `!`: the fork's `.action-button` sets its display outside the
          utility layer, which would otherwise win over `hidden`. --%>
    <.action_button
      variant={:secondary}
      size={:sm}
      icon="hero-plus-circle-mini"
      class="hidden! sm:inline-flex!"
      phx-click="show_create_form"
      phx-target={@myself}
    >
      {dgettext("dashboard_calendar", "Quick add")}
    </.action_button>
    """
  end

  attr :myself, :any, required: true

  # Opens the `.ics` import modal. Shown at every width, since nothing else
  # reaches the import on a phone; the label collapses to the icon below md, as
  # Refresh does, so the tools row still fits on one line at 390px.
  defp import_button(assigns) do
    ~H"""
    <.action_button
      variant={:secondary}
      size={:sm}
      icon="hero-arrow-up-tray-mini"
      class="shrink-0"
      phx-click="show_ics_import"
      phx-target={@myself}
      data-testid="import-ics-button"
      aria-label={dgettext("dashboard_calendar", "Import events from an .ics file")}
    >
      <span class="hidden md:inline">{dgettext("dashboard_calendar", "Import")}</span>
    </.action_button>
    """
  end

  attr :syncing, :boolean, required: true
  attr :myself, :any, required: true

  defp refresh_button(assigns) do
    ~H"""
    <%!-- The icon is in the slot rather than `icon` so it can spin while syncing. --%>
    <.action_button
      variant={:secondary}
      size={:sm}
      disabled={@syncing}
      phx-click={
        JS.push("refresh", target: @myself)
        |> JS.dispatch("calendar:scroll-to-current", to: "#calendar-drag-zone")
      }
      aria-label={dgettext("dashboard_calendar", "Refresh")}
    >
      <.icon
        name="hero-arrow-path"
        class={if @syncing, do: "w-4 h-4 shrink-0 animate-spin", else: "w-4 h-4 shrink-0"}
      />
      <span class="hidden md:inline">{dgettext("dashboard_calendar", "Refresh")}</span>
    </.action_button>
    """
  end

  attr :synced_at, :any, required: true

  # Plain muted text, not a button: mirrors `AvailabilityHelpers.timezone_display`'s
  # non-interactive icon+text treatment rather than the row's bordered buttons,
  # since there is nothing to click. Hidden below `sm` alongside `quick_add` so
  # the tools row keeps its icon buttons reachable on the narrowest screens.
  defp last_sync_indicator(assigns) do
    ~H"""
    <div class="hidden sm:flex items-center gap-1.5 text-token-sm text-neutral-500 dark:text-neutral-400 ml-1">
      <.icon name="hero-clock" class="w-3.5 h-3.5 shrink-0" />
      <span>{dgettext("dashboard_calendar", "Synced %{age}", age: Helpers.format_sync_age(@synced_at))}</span>
    </div>
    """
  end
end
