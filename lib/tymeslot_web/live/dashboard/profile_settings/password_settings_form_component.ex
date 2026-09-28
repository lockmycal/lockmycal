defmodule TymeslotWeb.Dashboard.ProfileSettings.PasswordSettingsFormComponent do
  @moduledoc """
  Password settings for the Profile page. Moved here from the old standalone
  `/dashboard/account` page. A successful change signs the user out (their
  password hash rotates) so they're redirected to log back in.

  The form is always visible (no "Change Password" reveal toggle), matching
  `UsernameFormComponent`'s always-visible input+button layout.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Auth
  alias TymeslotWeb.Dashboard.ProfileSettings.AccountSecurityForms, as: Forms
  alias TymeslotWeb.Dashboard.ProfileSettings.AccountSecurityHelpers, as: SecurityHelpers
  alias TymeslotWeb.Helpers.ClientIP

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, form_errors: %{}, saving: false)}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:is_social_user, SecurityHelpers.social_user?(assigns.current_user))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("update_password", %{"password_form" => params}, socket) do
    if socket.assigns.is_social_user do
      {:noreply, Flash.put_flash(socket, :error, social_user_message(socket))}
    else
      update_password(socket, params)
    end
  end

  defp update_password(socket, params) do
    socket = assign(socket, :saving, true)

    # Every rule (rate limit, current password, new-password policy,
    # confirmation, differing from the current one) is the domain's;
    # restating any of them here would let the two drift.
    case Auth.update_user_password(
           socket.assigns.current_user,
           params["current_password"],
           params["new_password"],
           params["new_password_confirmation"],
           ClientIP.request_opts(socket)
         ) do
      # A flash set right before the redirect travels with it; forwarding it
      # via `Flash` would race the teardown the redirect triggers.
      {:ok, _updated_user} ->
        # credo:disable-for-lines:4 CredoChecks.PutFlashInLiveComponent
        {:noreply,
         socket
         |> put_flash(
           :info,
           dgettext(
             "dashboard_profile",
             "Your password has been changed. Please sign in again with your new password."
           )
         )
         |> redirect(to: ~p"/auth/login")}

      {:error, :rate_limited, message} ->
        {:noreply, socket |> Flash.put_flash(:error, message) |> assign(:saving, false)}

      {:error, errors} ->
        {:noreply,
         socket
         |> assign(:form_errors, SecurityHelpers.field_errors(errors))
         |> assign(:saving, false)}
    end
  end

  defp social_user_message(socket) do
    provider = String.capitalize(socket.assigns.current_user.provider || "social")

    dgettext(
      "dashboard_profile",
      "Password authentication is not available for %{provider} login",
      provider: provider
    )
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="password-settings-form-container">
      <.subsection_header
        icon="hero-lock-closed"
        title={dgettext("dashboard_profile", "Password")}
        class="mb-3"
      />

      <%= if @is_social_user do %>
        <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
          {dgettext(
            "dashboard_profile",
            "Authentication is managed through %{provider} — password login isn't available for social accounts.",
            provider: String.capitalize(@current_user.provider || "social")
          )}
        </p>
      <% else %>
        <Forms.password_form errors={@form_errors} saving={@saving} myself={@myself} />
        <p class="mt-4 text-token-sm font-medium text-neutral-600 dark:text-neutral-300">
          {dgettext("dashboard_profile", "Last changed:")}
          <span class="font-bold text-neutral-800 dark:text-neutral-100">{SecurityHelpers.format_last_password_change(
            @current_user
          )}</span>
        </p>
      <% end %>
    </div>
    """
  end
end
