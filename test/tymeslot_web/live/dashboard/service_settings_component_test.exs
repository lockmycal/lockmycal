defmodule TymeslotWeb.Dashboard.ServiceSettingsComponentTest do
  @moduledoc """
  Server-side defense-in-depth for `:custom_booking_link_allowed` gating —
  `open_slug_modal` must refuse to open the slug modal for a stale
  client/hand-crafted event even though `ComponentView.settings/1` already
  disables the button, same reasoning and technique as
  `TymeslotWeb.Dashboard.ProfileSettings.UsernameFormComponentTest`. UI
  rendering is covered by
  `TymeslotWeb.Dashboard.MeetingSettingsBookingLinkGatingTest`.
  """

  use TymeslotWeb.ConnCase, async: true

  @moduletag :meeting_types

  import Tymeslot.Factory

  alias Phoenix.LiveView.Socket
  alias TymeslotWeb.Dashboard.ServiceSettingsComponent

  defp build_socket(assigns) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      endpoint: TymeslotWeb.Endpoint
    }
  end

  test "open_slug_modal is rejected, and the modal stays closed, when custom_booking_link_allowed is false" do
    meeting_type = insert(:meeting_type)

    socket =
      build_socket(%{
        custom_booking_link_allowed: false,
        editing_type: meeting_type,
        show_slug_modal: false
      })

    assert {:noreply, unchanged_socket} =
             ServiceSettingsComponent.handle_event("open_slug_modal", %{}, socket)

    assert unchanged_socket.assigns.show_slug_modal == false
    assert_received {:flash, {:error, _message}}
  end
end
