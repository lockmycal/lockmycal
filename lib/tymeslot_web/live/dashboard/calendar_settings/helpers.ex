defmodule TymeslotWeb.Dashboard.CalendarSettings.Helpers do
  @moduledoc """
  Helper functions for calendar settings dashboard.
  """
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.DisplayHelpers

  @spec format_provider_name(String.t() | atom()) :: String.t()
  def format_provider_name(provider) do
    DisplayHelpers.format_provider_display_name(provider)
  end

  @spec needs_scope_upgrade?(map()) :: boolean()
  def needs_scope_upgrade?(integration) do
    Calendar.needs_scope_upgrade?(integration)
  end

  @spec format_refresh_failures([String.t()]) :: String.t()
  def format_refresh_failures(names) when length(names) <= 3 do
    Enum.join(names, ", ")
  end

  @spec format_refresh_failures([String.t()]) :: String.t()
  def format_refresh_failures(names) do
    shown = names |> Enum.take(3) |> Enum.join(", ")
    remaining = length(names) - 3

    dngettext(
      "dashboard_calendar_settings",
      "%{shown} and %{count} more",
      "%{shown} and %{count} more",
      remaining,
      shown: shown,
      count: remaining
    )
  end

  @spec visible_hours_error_message(Ecto.Changeset.t()) :: String.t()
  def visible_hours_error_message(changeset) do
    case changeset.errors[:public_calendar_visible_to] do
      nil ->
        dgettext("dashboard_calendar_settings", "Failed to update visible hours")

      _error ->
        dgettext("dashboard_calendar_settings", "End time must be after the start time")
    end
  end
end
