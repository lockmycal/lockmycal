defmodule Tymeslot.Dashboard.CalendarConnectionTag do
  @moduledoc """
  Behaviour for an extra type tag on a connected-calendar row of the
  dashboard's Calendars page
  (`TymeslotWeb.Dashboard.CalendarSettings.CalendarConnectionRow`) — the small
  uppercase label Core itself uses for "Read-only".

  Same rationale as `Tymeslot.Dashboard.CalendarSettingsSection`: an external
  application (e.g. a paid overlay hosting calendars itself) can mark the
  integrations it created without Core knowing about it.

  ## Usage

      config :tymeslot, :calendar_connection_tags, [MyApp.Dashboard.HostedCalendarTag]

  The first module returning a label wins; Core's own "Read-only" tag takes
  precedence over all of them. `tag/1` runs on every re-render of every row,
  so it must not hit the database — decide from the integration's own fields.
  """

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema

  @doc "The translated label for this integration, or `nil` for none."
  @callback tag(integration :: CalendarIntegrationSchema.t()) :: String.t() | nil

  @doc "Reads the registered tag modules from config."
  @spec registered() :: [module()]
  def registered do
    Application.get_env(:tymeslot, :calendar_connection_tags, [])
  end

  @doc "The first label a registered module returns for `integration`, or `nil`."
  @spec for_integration(CalendarIntegrationSchema.t()) :: String.t() | nil
  def for_integration(integration) do
    Enum.find_value(registered(), & &1.tag(integration))
  end
end
