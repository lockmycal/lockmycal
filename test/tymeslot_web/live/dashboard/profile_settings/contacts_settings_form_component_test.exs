defmodule TymeslotWeb.Dashboard.ProfileSettings.ContactsSettingsFormComponentTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :profiles

  import Phoenix.LiveViewTest
  import Tymeslot.Factory

  alias Phoenix.LiveView.Socket
  alias Tymeslot.Profiles
  alias TymeslotWeb.Dashboard.ProfileSettings.ContactsSettingsFormComponent

  defp build_socket(assigns) do
    %Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns),
      endpoint: TymeslotWeb.Endpoint
    }
  end

  test "renders the toggle when contacts_allowed is true" do
    profile = build(:profile, contacts_enabled: false)

    html =
      render_component(ContactsSettingsFormComponent,
        id: "contacts-settings-form",
        profile: profile,
        contacts_allowed: true
      )

    assert html =~ "Collect contacts?"
    refute html =~ "Only available on the Pro plan and above."
  end

  test "defaults to allowed when the assign is omitted (self-host convention)" do
    profile = build(:profile, contacts_enabled: false)

    html =
      render_component(ContactsSettingsFormComponent,
        id: "contacts-settings-form",
        profile: profile
      )

    assert html =~ "Collect contacts?"
  end

  test "replaces the toggle and description with a locked notice when contacts_allowed is false" do
    profile = build(:profile, contacts_enabled: false)

    html =
      render_component(ContactsSettingsFormComponent,
        id: "contacts-settings-form",
        profile: profile,
        contacts_allowed: false
      )

    assert html =~ "Only available on the Pro plan and above."
    refute html =~ "Collect contacts?"
  end

  test "defaults to allowed when the assign is explicitly nil" do
    profile = build(:profile, contacts_enabled: false)

    html =
      render_component(ContactsSettingsFormComponent,
        id: "contacts-settings-form",
        profile: profile,
        contacts_allowed: nil
      )

    assert html =~ "Collect contacts?"
    refute html =~ "Only available on the Pro plan and above."
  end

  test "toggle_contacts_enabled persists the change when contacts_allowed is true" do
    profile = insert(:profile, contacts_enabled: false)
    socket = build_socket(%{contacts_allowed: true, profile: profile})

    assert {:noreply, updated_socket} =
             ContactsSettingsFormComponent.handle_event(
               "toggle_contacts_enabled",
               %{"state" => "true"},
               socket
             )

    assert updated_socket.assigns.profile.contacts_enabled
    assert_received {:flash, {:info, _message}}
    assert_received {:profile_updated, %{contacts_enabled: true}}
  end

  test "toggle_contacts_enabled is rejected server-side when contacts_allowed is false" do
    profile = insert(:profile, contacts_enabled: false)
    socket = build_socket(%{contacts_allowed: false, profile: profile})

    assert {:noreply, unchanged_socket} =
             ContactsSettingsFormComponent.handle_event(
               "toggle_contacts_enabled",
               %{"state" => "true"},
               socket
             )

    assert unchanged_socket.assigns.profile.contacts_enabled == false
    assert_received {:flash, {:error, _message}}
    refute_received {:profile_updated, _profile}

    # Not just socket-local: nothing was ever written to the database either
    # (a stale client resending the event twice must stay a no-op both times).
    refute Profiles.get_profile(profile.user_id).contacts_enabled
  end
end
