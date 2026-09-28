defmodule TymeslotWeb.Dashboard.ProfileSettings.UsernameFormComponentTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :profiles

  import Phoenix.LiveViewTest
  import Tymeslot.Factory

  alias Phoenix.LiveView.Socket
  alias Tymeslot.Profiles
  alias TymeslotWeb.Dashboard.ProfileSettings.UsernameFormComponent

  defp build_socket(assigns) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      endpoint: TymeslotWeb.Endpoint
    }
  end

  test "renders the editable form when custom_username_allowed is true" do
    profile = build(:profile, username: "current-handle")

    html =
      render_component(UsernameFormComponent,
        id: "username-form",
        profile: profile,
        custom_username_allowed: true
      )

    assert html =~ "Update URL"
    refute html =~ "Only available on the Pro plan and above."
  end

  test "defaults to allowed when the assign is omitted (self-host convention)" do
    profile = build(:profile, username: "current-handle")

    html = render_component(UsernameFormComponent, id: "username-form", profile: profile)

    assert html =~ "Update URL"
  end

  test "defaults to allowed when the assign is explicitly nil" do
    profile = build(:profile, username: "current-handle")

    html =
      render_component(UsernameFormComponent,
        id: "username-form",
        profile: profile,
        custom_username_allowed: nil
      )

    assert html =~ "Update URL"
  end

  test "replaces the form with a read-only link and locked notice when custom_username_allowed is false" do
    profile = build(:profile, username: "current-handle")

    html =
      render_component(UsernameFormComponent,
        id: "username-form",
        profile: profile,
        custom_username_allowed: false
      )

    assert html =~ "Only available on the Pro plan and above."
    assert html =~ "current-handle"
    refute html =~ "Update URL"
  end

  test "update_username is rejected server-side, and nothing is persisted, when custom_username_allowed is false" do
    user = insert(:user)
    profile = insert(:profile, user: user, username: "locked-in")
    socket = build_socket(%{custom_username_allowed: false, profile: profile})

    assert {:noreply, unchanged_socket} =
             UsernameFormComponent.handle_event(
               "update_username",
               %{"username" => "attempted-change"},
               socket
             )

    assert unchanged_socket.assigns.profile.username == "locked-in"
    assert_received {:flash, {:error, _message}}

    # Not just socket-local: nothing was ever written to the database either
    # (a stale client resending the event twice must stay a no-op both times).
    assert Profiles.get_profile(user.id).username == "locked-in"
  end

  test "check_username_availability is a no-op when custom_username_allowed is false" do
    profile = build(:profile, username: "locked-in")
    socket = build_socket(%{custom_username_allowed: false, profile: profile})

    assert {:noreply, unchanged_socket} =
             UsernameFormComponent.handle_event(
               "check_username_availability",
               %{"username" => "someone-else"},
               socket
             )

    assert unchanged_socket.assigns[:username_check] == nil
    assert unchanged_socket.assigns[:username_available] == nil
  end
end
