defmodule TymeslotWeb.Dashboard.CalendarSettings.Components do
  @moduledoc """
  Functional components for the calendar settings dashboard.

  The connected-calendar row itself and its summary text are their own
  module, `TymeslotWeb.Dashboard.CalendarSettings.CalendarConnectionRow`.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Dashboard.Integrations.Calendar.{
    AppleConfig,
    BaikalConfig,
    CaldavConfig,
    ExchangeConfig,
    IcsUrlConfig,
    MailboxOrgConfig,
    NextcloudConfig,
    RadicaleConfig,
    ZimbraConfig
  }

  alias TymeslotWeb.Dashboard.CalendarSettings.CalendarConnectionRow

  @doc "Renders the configuration view for a specific calendar provider."
  attr :selected_provider, :atom, required: true
  attr :myself, :any, required: true
  attr :security_metadata, :map, required: true
  attr :form_errors, :map, required: true
  attr :form_values, :map, required: true
  attr :discovered_calendars, :list, required: true
  attr :show_calendar_selection, :boolean, required: true
  attr :discovery_credentials, :map, required: true
  attr :is_saving, :boolean, required: true

  @spec config_view(map()) :: Phoenix.LiveView.Rendered.t()
  def config_view(assigns) do
    ~H"""
    <div id="calendar-config-view" phx-hook="ScrollReset" data-action={@selected_provider}>
      <%= case @selected_provider do %>
        <% :nextcloud -> %>
          <.live_component
            module={NextcloudConfig}
            id="nextcloud-config"
            target={@myself}
            metadata={@security_metadata}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% :radicale -> %>
          <.live_component
            module={RadicaleConfig}
            id="radicale-config"
            target={@myself}
            metadata={@security_metadata}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% :baikal -> %>
          <.live_component
            module={BaikalConfig}
            id="baikal-config"
            target={@myself}
            metadata={@security_metadata}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% :caldav -> %>
          <.live_component
            module={CaldavConfig}
            id="caldav-config"
            target={@myself}
            metadata={@security_metadata}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% :zimbra -> %>
          <.live_component
            module={ZimbraConfig}
            id="zimbra-config"
            target={@myself}
            metadata={@security_metadata}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% :mailbox_org -> %>
          <.live_component
            module={MailboxOrgConfig}
            id="mailbox-org-config"
            target={@myself}
            metadata={@security_metadata}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% :ics_url -> %>
          <.live_component
            module={IcsUrlConfig}
            id="ics-url-config"
            target={@myself}
            form_errors={@form_errors}
            form_values={@form_values}
            saving={@is_saving}
          />
        <% :exchange -> %>
          <.live_component
            module={ExchangeConfig}
            id="exchange-config"
            target={@myself}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% :apple -> %>
          <.live_component
            module={AppleConfig}
            id="apple-config"
            target={@myself}
            metadata={@security_metadata}
            form_errors={@form_errors}
            form_values={@form_values}
            discovered_calendars={@discovered_calendars}
            show_calendar_selection={@show_calendar_selection}
            discovery_credentials={@discovery_credentials}
            saving={@is_saving}
          />
        <% _ -> %>
          <p class="text-neutral-500 dark:text-twilight-indigo-200 font-medium">
            {dgettext(
              "dashboard_calendar_settings",
              "Configuration form not available for this provider."
            )}
          </p>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders the free/busy feed section: the read-only iCalendar link that
  publishes when the user is busy, and the controls to enable, regenerate, or
  disable it.
  """
  attr :enabled, :boolean, required: true
  attr :url, :string, default: nil
  attr :myself, :any, required: true

  @spec freebusy_section(map()) :: Phoenix.LiveView.Rendered.t()
  def freebusy_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <.subsection_header
        icon="hero-link"
        title={dgettext("dashboard_calendar_settings", "Free/busy feed")}
      />

      <div class="card-glass p-4 space-y-3">
        <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
          {dgettext(
            "dashboard_calendar_settings",
            "Share a read-only link that publishes when you're busy (not the event details) as a standard iCalendar feed, so other calendar systems can overlay your availability."
          )}
        </p>

        <%= if @enabled do %>
          <code class="block w-full overflow-x-auto rounded-token-md bg-neutral-50 dark:bg-twilight-indigo-900/60 px-3 py-2 text-token-sm text-neutral-700 dark:text-neutral-200 select-all">
            {@url}
          </code>
          <div class="flex flex-wrap justify-end gap-2">
            <button
              type="button"
              class="btn btn-secondary"
              phx-click="regenerate_freebusy"
              phx-target={@myself}
            >
              {dgettext("dashboard_calendar_settings", "Regenerate link")}
            </button>
            <button
              type="button"
              class="btn btn-danger"
              phx-click="disable_freebusy"
              phx-target={@myself}
            >
              {dgettext("dashboard_calendar_settings", "Disable feed")}
            </button>
          </div>
        <% else %>
          <button
            type="button"
            class="btn btn-primary"
            phx-click="enable_freebusy"
            phx-target={@myself}
          >
            {dgettext("dashboard_calendar_settings", "Enable free/busy feed")}
          </button>
        <% end %>
      </div>
    </section>
    """
  end

  @doc "Renders the section for already connected calendars."
  attr :integrations, :list, required: true
  attr :is_refreshing, :boolean, required: true
  attr :myself, :any, required: true
  attr :health_states, :map, default: %{}
  attr :limit_reached, :boolean, default: false
  attr :activation_reached, :boolean, default: false

  @spec connected_calendars_section(map()) :: Phoenix.LiveView.Rendered.t()
  def connected_calendars_section(assigns) do
    # Group integrations by active/inactive
    {active, inactive} = Enum.split_with(assigns.integrations, & &1.is_active)

    assigns =
      assigns
      |> assign(:active_integrations, active)
      |> assign(:inactive_integrations, inactive)

    ~H"""
    <div :if={@integrations != []} class="space-y-12">
      <%!-- Active Calendars Section --%>
      <div :if={@active_integrations != []} class="space-y-6">
        <div class="flex items-center justify-between gap-4 flex-col md:flex-row">
          <div>
            <.subsection_header
              icon="hero-shield-check"
              title={dgettext("dashboard_calendar_settings", "Active for Conflict Checking")}
              count={length(@active_integrations)}
            />
            <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200 mt-1 ml-7">
              {dgettext(
                "dashboard_calendar_settings",
                "We'll check these calendars to prevent double bookings automatically."
              )}
            </p>
          </div>

          <.section_actions
            myself={@myself}
            is_refreshing={@is_refreshing}
            limit_reached={@limit_reached}
          />
        </div>

        <div class="grid grid-cols-1 gap-4">
          <%= for integration <- @active_integrations do %>
            <CalendarConnectionRow.calendar_connection_row
              integration={integration}
              myself={@myself}
              health_state={Map.get(@health_states, integration.id)}
            />
          <% end %>
        </div>
      </div>

      <%!-- Inactive Calendars Section --%>
      <div :if={@inactive_integrations != []} class="space-y-6">
        <div class="flex items-center justify-between gap-4 flex-col md:flex-row">
          <div>
            <.subsection_header
              icon="hero-pause-circle"
              title={dgettext("dashboard_calendar_settings", "Paused Calendars")}
              count={length(@inactive_integrations)}
              muted
            />
            <p class="text-token-sm text-neutral-400 mt-1 ml-7">
              {dgettext(
                "dashboard_calendar_settings",
                "These calendars are currently ignored during conflict checking."
              )}
            </p>
          </div>

          <%!-- Only when no active section is shown, so the actions always render exactly once --%>
          <.section_actions
            :if={@active_integrations == []}
            myself={@myself}
            is_refreshing={@is_refreshing}
            limit_reached={@limit_reached}
          />
        </div>

        <div class="grid grid-cols-1 gap-4">
          <%= for integration <- @inactive_integrations do %>
            <CalendarConnectionRow.calendar_connection_row
              integration={integration}
              myself={@myself}
              health_state={Map.get(@health_states, integration.id)}
              activation_blocked={@activation_reached}
            />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :is_refreshing, :boolean, required: true
  attr :limit_reached, :boolean, default: false

  defp section_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-2 shrink-0">
      <button
        phx-click="refresh_all_calendars"
        phx-target={@myself}
        class="btn btn-secondary inline-flex items-center gap-2"
        disabled={@is_refreshing}
      >
        <svg
          class={["w-4 h-4", @is_refreshing && "animate-spin"]}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2.5"
            d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
          />
        </svg>
        {if @is_refreshing,
          do: dgettext("dashboard_calendar_settings", "Refreshing..."),
          else: dgettext("dashboard_calendar_settings", "Refresh All")}
      </button>
      <button
        phx-click="show_picker"
        phx-target={@myself}
        class="btn btn-primary inline-flex items-center gap-1.5"
        disabled={@limit_reached}
      >
        <.icon name="hero-plus" class="w-4 h-4" />
        {dgettext("dashboard_calendar_settings", "Connect a calendar")}
      </button>
    </div>
    """
  end
end
