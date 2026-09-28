defmodule TymeslotWeb.Hooks.DashboardInitHookPaymentsTest do
  @moduledoc """
  Covers `DashboardInitHook`'s `payments_allowed` assign once meeting
  payments are turned on, kept out of `DashboardInitHookTest` because it
  mutates the `meeting_payments_enabled` global — same reasoning as
  `Tymeslot.Features.DefaultAccessCheckerTest`, which touches the same
  config key.
  """

  use TymeslotWeb.ConnCase, async: false

  @moduletag :utils

  import Tymeslot.Factory
  import Tymeslot.ConfigTestHelpers

  alias Phoenix.LiveView.Socket
  alias TymeslotWeb.Hooks.DashboardInitHook

  defp build_socket(assigns) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      endpoint: TymeslotWeb.Endpoint
    }
  end

  test "unlocks payments access once meeting payments are enabled" do
    with_config(:tymeslot, :meeting_payments_enabled, true)

    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    socket = build_socket(%{current_user: user})

    assert {:cont, updated_socket} = DashboardInitHook.on_mount(:default, %{}, %{}, socket)
    assert updated_socket.assigns.payments_allowed
  end
end
