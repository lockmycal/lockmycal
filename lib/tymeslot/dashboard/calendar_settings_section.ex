defmodule Tymeslot.Dashboard.CalendarSettingsSection do
  @moduledoc """
  Behaviour for an extra section on the dashboard's Calendars page
  (`TymeslotWeb.Dashboard.CalendarSettings.ComponentView`), rendered right
  after the connected-calendars list.

  Same rationale as `Tymeslot.Dashboard.OverviewWidget`: Core defines the
  contract, an external application (e.g. a paid overlay offering a hosted
  calendar) implements it and registers itself — Core never names the
  external application, imports from it, or checks whether one is present.

  ## Usage

  Register one or more modules via `config/runtime.exs`:

      config :tymeslot, :calendar_settings_extra_sections, [
        MyApp.Dashboard.HostedCalendarSection
      ]

  Each renders in list order. An empty or unset list (the default) leaves the
  page exactly as it is.

  `render/2` returns the whole section, or `nil` to show nothing for this
  user. It gets the user's connected calendar integrations too and is called
  again whenever they change (one is connected, updated or deleted), so a
  section tied to one of them can react; it should stay cheap.
  A section that handles its own events should render a nested
  `Phoenix.LiveComponent`; after it changes the user's integrations it can
  `send(self(), {:integration_added, :calendar})` so the connected list
  refreshes, exactly as Core's own connect flow does.
  """

  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema

  @doc "The section's identifier; used as its DOM id suffix, so keep it unique."
  @callback id() :: atom()

  @doc """
  Renders the section for the user viewing the page and their connected
  calendar integrations, or `nil` to skip it.
  """
  @callback render(user :: UserSchema.t(), integrations :: [CalendarIntegrationSchema.t()]) ::
              Phoenix.LiveView.Rendered.t() | nil

  @doc """
  Reads the registered section modules from config. Not validated, for the
  same reason `Tymeslot.Dashboard.OverviewWidget.registered/0` isn't.
  """
  @spec registered() :: [module()]
  def registered do
    Application.get_env(:tymeslot, :calendar_settings_extra_sections, [])
  end
end
