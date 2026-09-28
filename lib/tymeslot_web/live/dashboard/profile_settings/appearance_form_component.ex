defmodule TymeslotWeb.Dashboard.ProfileSettings.AppearanceFormComponent do
  @moduledoc """
  Appearance form component for profile settings.

  Lets the organiser choose whether the dashboard renders Light, Dark, or
  follows the browser's own "System" (prefers-color-scheme) setting. Unlike
  the language preference, this is pure CSS — no remount is needed, just a
  saved preference plus an immediate client-side class flip (see the
  `AppearanceToggle` hook) so the change is visible without waiting on the
  next full page load.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Auth

  @impl Phoenix.LiveComponent
  def handle_event("change_appearance", %{"option" => option}, socket) do
    theme_preference = if option == "system", do: nil, else: option

    case Auth.update_user_theme_preference(socket.assigns.current_user, theme_preference) do
      {:ok, updated_user} ->
        Flash.info(dgettext("dashboard_profile", "Appearance updated"))
        {:noreply, assign(socket, current_user: updated_user)}

      {:error, _changeset} ->
        Flash.error(dgettext("dashboard_profile", "Failed to update appearance"))
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="appearance-form-container" phx-hook="AppearanceToggle">
      <.subsection_header
        icon="hero-swatch"
        title={dgettext("dashboard_profile", "Appearance")}
        class="mb-3"
      />
      <div class="input p-4">
        <div class="flex items-center justify-between gap-4">
          <span class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_profile", "Choose how the dashboard looks")}
          </span>
          <.option_toggle
            active_value={@current_user.theme_preference || "system"}
            click_event="change_appearance"
            target={@myself}
            aria_label={dgettext("dashboard_profile", "Set appearance")}
            options={[
              {"light", dgettext("dashboard_profile", "Light")},
              {"dark", dgettext("dashboard_profile", "Dark")},
              {"system", dgettext("dashboard_profile", "System")}
            ]}
          />
        </div>
      </div>
      <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
        {dgettext("dashboard_profile", "\"System\" follows your device's light/dark setting.")}
      </p>
    </div>
    """
  end
end
