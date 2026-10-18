defmodule TymeslotWeb.Dashboard.ThemeSettings.IcsBrandingComponent do
  @moduledoc """
  The Appearance page's switch for the "Scheduled with <app>" line at the end of
  the calendar files sent about the organiser's meetings
  (`Tymeslot.Profiles.IcsBranding`).

  Shown only to an organiser whose plan allows custom branding (the same gate
  as their own logo, `custom_branding_allowed`) and only on an instance that
  adds the line at all; everyone else always gets it.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.IcsBranding
  alias TymeslotWeb.Live.Shared.Flash

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:custom_branding_allowed, fn -> true end)
     |> assign(:available, IcsBranding.url() != nil)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <%!-- `setting_row` is a card of its own. --%>
      <div :if={@custom_branding_allowed and @available} class="mt-6 max-w-2xl">
        <.setting_row
          id={"#{@id}-toggle"}
          control={:switch}
          label={
            dgettext("dashboard_appearance", "\"Scheduled with %{app}\" in calendar files",
              app: Config.app_name()
            )
          }
          description={
            dgettext(
              "dashboard_appearance",
              "The calendar invitations and downloads for your meetings end their description with this line and a link. Turn it off to leave it out."
            )
          }
          checked={@profile.ics_branding_enabled}
          phx-value-state={to_string(!@profile.ics_branding_enabled)}
          on_change="toggle_ics_branding"
          target={@myself}
        />
      </div>
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle_ics_branding", %{"state" => state}, socket) do
    profile = socket.assigns.profile

    with true <- IcsBranding.allowed?(profile),
         {:ok, updated} <-
           Profiles.update_profile_field(profile, :ics_branding_enabled, state == "true") do
      send(self(), {:profile_updated, updated})
      {:noreply, assign(socket, :profile, updated)}
    else
      _refused ->
        {:noreply,
         Flash.put_flash(
           socket,
           :error,
           dgettext("dashboard_appearance", "Could not save the setting.")
         )}
    end
  end
end
