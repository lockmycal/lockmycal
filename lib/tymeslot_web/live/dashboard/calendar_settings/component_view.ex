defmodule TymeslotWeb.Dashboard.CalendarSettings.ComponentView do
  @moduledoc """
  Markup for the calendar settings component.

  Extracted from `CalendarSettingsComponent` so that module stays focused on
  lifecycle and event routing, matching how `CalendarGrid.ComponentView` sits
  behind `CalendarGridComponent`. `settings/1` receives the component's assigns
  unchanged (its `render/1` delegates straight to it), so LiveView change
  tracking is preserved.

  The picker groups come from `ProviderPicker`, which owns how provider
  descriptors are categorised for that one modal.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias TymeslotWeb.Components.Dashboard.Integrations.Calendar.CaldavReconnectModal
  alias TymeslotWeb.Components.Dashboard.Integrations.Calendar.CalendarSelectionModal
  alias TymeslotWeb.Components.Dashboard.Integrations.Calendar.ConnectionLimit
  alias TymeslotWeb.Components.Dashboard.Integrations.Shared.DeleteIntegrationModal
  alias TymeslotWeb.Components.Dashboard.Integrations.Shared.ProviderPickerModal
  alias TymeslotWeb.Dashboard.CalendarSettings.Components
  alias TymeslotWeb.Dashboard.CalendarSettings.ConfigViewComponent
  alias TymeslotWeb.Dashboard.CalendarSettings.ProviderPicker
  alias TymeslotWeb.Dashboard.CalendarSettings.PublicCalendarSection

  @doc "Renders calendar settings: the connected list, the free/busy feed, the public calendar block (visibility, colours, visible hours, historical events), and the modal stack."
  @spec settings(map()) :: Phoenix.LiveView.Rendered.t()
  def settings(assigns) do
    ~H"""
    <div class="space-y-12 pb-24">
      <.section_header
        icon="hero-calendar-days"
        title={dgettext("dashboard_calendar_settings", "Calendars")}
        subtitle={
          dgettext(
            "dashboard_calendar_settings",
            "Connect your calendars to check availability and prevent double bookings."
          )
        }
      />

      <div class="space-y-12">
        <div class="space-y-6">
          <ConnectionLimit.connection_limit_notice limit={@connection_limit} />
          <%= if @integrations == [] do %>
            <.no_calendars_yet myself={@myself} limit_reached={@connection_limit.reached?} />
          <% else %>
            <Components.connected_calendars_section
              integrations={@integrations}
              is_refreshing={@is_refreshing}
              myself={@myself}
              health_states={@health_states}
              limit_reached={@connection_limit.reached?}
              activation_reached={@connection_limit.activation_reached?}
            />
          <% end %>
        </div>

        <Components.freebusy_section
          enabled={@freebusy_enabled}
          url={@freebusy_url}
          myself={@myself}
        />

        <PublicCalendarSection.public_calendar_section profile={@freebusy_profile} myself={@myself} />
      </div>

      <ProviderPickerModal.provider_picker_modal
        id="calendar-provider-picker"
        show={@show_picker}
        title={dgettext("dashboard_calendar_settings", "Connect a calendar")}
        subtitle={
          dgettext(
            "dashboard_calendar_settings",
            "Sync your availability to prevent double bookings."
          )
        }
        target={@myself}
        on_cancel={JS.push("hide_picker", target: @myself)}
        groups={ProviderPicker.groups(@available_calendar_providers, @integrations)}
        config_active={@selected_provider != nil}
        back_event="back_to_grid"
      >
        <:config>
          <.live_component
            :if={@selected_provider != nil}
            module={ConfigViewComponent}
            id="calendar-config-view-component"
            selected_provider={@selected_provider}
            current_user={@current_user}
            security_metadata={@security_metadata}
          />
        </:config>
      </ProviderPickerModal.provider_picker_modal>

      <CalendarSelectionModal.calendar_selection_modal
        id="calendar-selection"
        show={@managing_calendar_id != nil}
        integration={Enum.find(@integrations, &(&1.id == @managing_calendar_id))}
        target={@myself}
        on_cancel={JS.push("close_manage_calendars", target: @myself)}
      />

      <.live_component
        module={DeleteIntegrationModal}
        id="delete-calendar-modal"
        integration_type={:calendar}
        current_user={@current_user}
      />

      <.live_component
        module={CaldavReconnectModal}
        id="caldav-reconnect-modal"
        current_user={@current_user}
      />
    </div>
    """
  end

  attr :myself, :any, required: true
  attr :limit_reached, :boolean, default: false

  defp no_calendars_yet(assigns) do
    ~H"""
    <div class="card-glass p-10 text-center">
      <div class="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-token-2xl bg-primary-50 text-primary-500">
        <.icon name="hero-calendar-days" class="h-7 w-7" />
      </div>
      <h3 class="text-token-lg font-semibold text-neutral-800 dark:text-neutral-100">
        {dgettext("dashboard_calendar_settings", "No calendars connected yet")}
      </h3>
      <p class="mx-auto mt-1 max-w-md pb-2 text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
        {dgettext(
          "dashboard_calendar_settings",
          "Connect a calendar so Tymeslot can read your availability and stop meetings being booked when you're already busy."
        )}
      </p>
      <button
        phx-click="show_picker"
        phx-target={@myself}
        class="btn btn-primary"
        disabled={@limit_reached}
      >
        <.icon name="hero-plus" class="w-4 h-4" /> {dgettext(
          "dashboard_calendar_settings",
          "Connect a calendar"
        )}
      </button>
    </div>
    """
  end
end
