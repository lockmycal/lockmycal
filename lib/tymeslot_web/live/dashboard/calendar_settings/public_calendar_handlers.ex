defmodule TymeslotWeb.Dashboard.CalendarSettings.PublicCalendarHandlers do
  @moduledoc """
  The Calendars page's free/busy feed and public calendar settings: loading
  them and handling their events.

  Extracted from `CalendarSettingsComponent` to keep that module under the
  large-module line limit. The component delegates the section's events here
  (`handle_event/3`), each returning the updated socket.
  """

  use TymeslotWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.FreeBusy
  alias Tymeslot.Profiles
  alias TymeslotWeb.Dashboard.CalendarSettings.Helpers
  alias TymeslotWeb.Live.Shared.Flash

  @flags %{
    "toggle_public_calendar_show_historical_events" => :public_calendar_show_historical_events,
    "toggle_public_calendar_show_weekends" => :public_calendar_show_weekends
  }

  @doc "Assigns the profile's free/busy feed and public calendar settings."
  @spec load(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load(socket) do
    case Profiles.get_or_create_profile(socket.assigns.current_user.id) do
      {:ok, profile} ->
        token = profile.freebusy_token

        socket
        |> assign(:freebusy_profile, profile)
        |> assign(:freebusy_enabled, FreeBusy.feed_enabled?(profile))
        |> assign(:freebusy_url, token && url(~p"/free-busy/#{token}"))

      _error ->
        socket
        |> assign(:freebusy_profile, nil)
        |> assign(:freebusy_enabled, false)
        |> assign(:freebusy_url, nil)
    end
  end

  defp update_freebusy(%{assigns: %{freebusy_profile: %{} = profile}} = socket, fun) do
    case fun.(profile) do
      {:ok, _updated} -> load(socket)
      {:error, _changeset} -> socket
    end
  end

  defp update_freebusy(socket, _fun), do: socket

  @doc "Handles one of the free/busy feed's or the public calendar's events."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("enable_freebusy", _params, socket) do
    update_freebusy(socket, &FreeBusy.enable_feed/1)
  end

  def handle_event("regenerate_freebusy", _params, socket) do
    update_freebusy(socket, &FreeBusy.regenerate_token/1)
  end

  def handle_event("disable_freebusy", _params, socket) do
    update_freebusy(socket, &FreeBusy.disable_feed/1)
  end

  def handle_event("toggle_public_calendar_colors", %{"state" => state}, socket) do
    update_freebusy(socket, fn profile ->
      Profiles.update_profile_field(
        profile,
        :public_calendar_colors,
        state == "true"
      )
    end)
  end

  def handle_event("toggle_public_calendar_colors", _params, socket) do
    update_freebusy(socket, fn profile ->
      Profiles.update_profile_field(
        profile,
        :public_calendar_colors,
        !profile.public_calendar_colors
      )
    end)
  end

  # Also tells DashboardLive, whose profile feeds the share-links dialog.
  def handle_event("toggle_public_calendar_enabled", %{"state" => state}, socket) do
    update_freebusy(socket, fn profile ->
      with {:ok, updated} <-
             Profiles.update_profile_field(profile, :public_calendar_enabled, state == "true") do
        send(self(), {:profile_updated, updated})
        {:ok, updated}
      end
    end)
  end

  def handle_event(event, _params, socket) when is_map_key(@flags, event) do
    field = Map.fetch!(@flags, event)

    update_freebusy(socket, &Profiles.update_profile_field(&1, field, !Map.fetch!(&1, field)))
  end

  # Turning the window on seeds it with a sensible default (9–5) rather than
  # leaving it half-configured — the changeset rejects one bound set without
  # the other (`ProfileSchema.validate_public_calendar_visible_hours/1`), so
  # "enabled" always means both fields are present. Turning it off clears
  # both, back to "no restriction".
  def handle_event("toggle_public_calendar_visible_hours", %{"state" => "true"}, socket) do
    update_freebusy(socket, fn profile ->
      Profiles.update_profile(profile, %{
        public_calendar_visible_from: profile.public_calendar_visible_from || ~T[09:00:00],
        public_calendar_visible_to: profile.public_calendar_visible_to || ~T[17:00:00]
      })
    end)
  end

  def handle_event("toggle_public_calendar_visible_hours", %{"state" => "false"}, socket) do
    update_freebusy(socket, fn profile ->
      Profiles.update_profile(profile, %{
        public_calendar_visible_from: nil,
        public_calendar_visible_to: nil
      })
    end)
  end

  def handle_event(
        "update_public_calendar_visible_hours",
        %{"from" => from, "to" => to},
        socket
      ) do
    case Profiles.update_profile(socket.assigns.freebusy_profile, %{
           public_calendar_visible_from: from,
           public_calendar_visible_to: to
         }) do
      {:ok, _updated} ->
        load(socket)

      {:error, changeset} ->
        Flash.error(Helpers.visible_hours_error_message(changeset))
        socket
    end
  end
end
