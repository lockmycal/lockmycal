defmodule TymeslotWeb.Dashboard.ProfileSettings.ContactsSettingsFormComponent do
  @moduledoc """
  "Collect contacts?" toggle for profile settings.

  When enabled, every new public booking captures/refreshes a Contacts row
  (name, email, phone, company) for the organizer. Disabling it stops new
  captures and hides the Contacts sidebar link, but never touches contacts
  already captured.

  Gated by the `contacts_allowed` assign (defaults to `true`, same
  self-host-open convention as the rest of `:feature_assigns` — see
  `TymeslotWeb.Hooks.FeatureAssignsHook`): when `false`, the toggle and its
  description are replaced by a plain locked notice instead of being
  rendered disabled, mirroring how `CustomQuestionsSection` locks itself.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Profiles

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    # `Map.get/2` folds an absent key and an explicit `contacts_allowed: nil`
    # into the same `nil` default case — a plain `Map.put_new/3` would only
    # catch the former, silently unlocking the toggle for a caller that ever
    # passes `nil` instead of omitting the key or passing `false`.
    contacts_allowed =
      case Map.get(assigns, :contacts_allowed) do
        nil -> true
        allowed -> allowed
      end

    {:ok, assign(socket, Map.put(assigns, :contacts_allowed, contacts_allowed))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle_contacts_enabled", %{"state" => state}, socket) do
    if socket.assigns.contacts_allowed do
      profile = socket.assigns.profile
      contacts_enabled = state == "true"

      case Profiles.update_profile_field(profile, :contacts_enabled, contacts_enabled) do
        {:ok, updated_profile} ->
          send(self(), {:profile_updated, updated_profile})
          Flash.info(contacts_flash_message(updated_profile.contacts_enabled))
          {:noreply, assign(socket, profile: updated_profile)}

        {:error, _changeset} ->
          Flash.error(
            dgettext("dashboard_profile", "Failed to update contact collection setting")
          )

          {:noreply, socket}
      end
    else
      # Defends against a stale client (toggle rendered before a plan
      # downgrade) or a hand-crafted LiveView event — render/1 already hides
      # the control itself when contacts_allowed is false.
      Flash.error(
        dgettext(
          "dashboard_profile",
          "Contact collection is available on the Pro plan and above."
        )
      )

      {:noreply, socket}
    end
  end

  defp contacts_flash_message(true),
    do: dgettext("dashboard_profile", "New bookings will now be added to your contacts")

  defp contacts_flash_message(false),
    do: dgettext("dashboard_profile", "New bookings will no longer be added to your contacts")

  @impl Phoenix.LiveComponent
  def render(%{contacts_allowed: false} = assigns) do
    ~H"""
    <div id="contacts-settings-form-container">
      <.subsection_header
        icon="hero-identification"
        title={dgettext("dashboard_profile", "Contact Collection")}
        class="mb-3"
      />
      <div class="input p-4">
        <p class="text-token-sm font-medium text-neutral-500 text-center">
          {dgettext("dashboard_profile", "Only available on the Pro plan and above.")}
        </p>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id="contacts-settings-form-container">
      <.subsection_header
        icon="hero-identification"
        title={dgettext("dashboard_profile", "Contact Collection")}
        class="mb-3"
      />
      <div class="input p-4">
        <div class="flex items-center justify-between gap-4">
          <span class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_profile", "Collect contacts?")}
          </span>
          <.enabled_toggle
            active={(@profile && @profile.contacts_enabled) || false}
            click_event="toggle_contacts_enabled"
            target={@myself}
            aria_label={dgettext("dashboard_profile", "Set contact collection")}
          />
        </div>
      </div>
      <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
        {dgettext(
          "dashboard_profile",
          "When enabled, each new public booking adds or updates a contact with the booker's name, email, phone, and company."
        )}
      </p>
    </div>
    """
  end
end
