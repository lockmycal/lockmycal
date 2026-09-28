defmodule TymeslotWeb.Live.Dashboard.Shared.DashboardHelpers do
  @moduledoc """
  Shared utility functions for dashboard components.
  Focuses on security metadata and client info.
  """

  alias TymeslotWeb.Helpers.ClientIP

  @doc """
  Gets remote IP from socket for security logging.
  """
  @spec get_remote_ip(Phoenix.LiveView.Socket.t()) :: String.t()
  def get_remote_ip(socket) do
    ClientIP.get(socket)
  end

  @doc """
  Gets security metadata from socket for input validation and logging.
  Provides consistent format across all dashboard components.
  Safe for both LiveViews and LiveComponents.
  """
  @spec get_security_metadata(Phoenix.LiveView.Socket.t()) :: map()
  def get_security_metadata(socket) do
    assigns = socket.assigns

    %{
      ip: compute_ip(assigns),
      user_agent: compute_user_agent(assigns),
      user_id: compute_user_id(assigns)
    }
  end

  defp compute_ip(assigns) do
    assigns[:client_ip] || "unknown"
  end

  defp compute_user_agent(assigns) do
    assigns[:user_agent] || "unknown"
  end

  defp compute_user_id(assigns) do
    cond do
      is_map_key(assigns, :current_user) and assigns.current_user ->
        assigns.current_user.id

      is_map_key(assigns, :profile) and assigns.profile ->
        Map.get(assigns.profile, :user_id) ||
          (Map.get(assigns.profile, :user) && Map.get(assigns.profile.user, :id))

      true ->
        nil
    end
  end
end
