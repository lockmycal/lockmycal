defmodule TymeslotWeb.Dashboard.ProfileSettings.EmailSettingsFormComponent do
  @moduledoc """
  Email address settings for the Profile page — request an email change
  (re-verified via a confirmation link sent to the new address) or cancel a
  pending one. Moved here from the old standalone `/dashboard/account` page.

  The form is always visible (no "Change Email" reveal toggle), matching
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
  def handle_event("update_email", %{"email_form" => params}, socket) do
    if socket.assigns.is_social_user do
      {:noreply, Flash.put_flash(socket, :error, social_user_message(socket))}
    else
      update_email(socket, params)
    end
  end

  def handle_event("cancel_email_change", _params, socket) do
    case Auth.cancel_email_change(socket.assigns.current_user) do
      {:ok, updated_user, message} ->
        send(self(), {:current_user_updated, updated_user})

        {:noreply,
         socket
         |> Flash.put_flash(:info, message)
         |> assign(:current_user, updated_user)}

      {:error, {_reason, message}} ->
        {:noreply, Flash.put_flash(socket, :error, message)}
    end
  end

  defp update_email(socket, params) do
    socket = assign(socket, :saving, true)

    # Every rule (rate limit, address format, current password) is the
    # domain's, which reports each field's problem at once.
    case Auth.request_email_change(
           socket.assigns.current_user,
           params["new_email"],
           params["current_password"],
           ClientIP.request_opts(socket)
         ) do
      {:ok, updated_user, message} ->
        send(self(), {:current_user_updated, updated_user})

        {:noreply,
         socket
         |> Flash.put_flash(:info, message)
         |> assign(current_user: updated_user, form_errors: %{}, saving: false)}

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

    dgettext("dashboard_profile", "Email changes are managed through your %{provider} account",
      provider: provider
    )
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="email-settings-form-container">
      <.subsection_header
        icon="hero-envelope"
        title={dgettext("dashboard_profile", "Email Address")}
        class="mb-3"
      />

      <%= if @is_social_user do %>
        <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
          {dgettext(
            "dashboard_profile",
            "Managed through your %{provider} account — email changes aren't available for social login accounts.",
            provider: String.capitalize(@current_user.provider || "social")
          )}
        </p>
      <% else %>
        <Forms.email_form errors={@form_errors} saving={@saving} myself={@myself} />
      <% end %>

      <p class="mt-4 text-token-sm font-medium text-neutral-600 dark:text-neutral-300">
        {dgettext("dashboard_profile", "Current email:")}
        <span class="font-bold text-neutral-800 dark:text-neutral-100">{@current_user.email}</span>
      </p>

      <.pending_email_notice
        :if={@current_user.pending_email}
        pending_email={@current_user.pending_email}
        email_change_sent_at={@current_user.email_change_sent_at}
        myself={@myself}
      />
    </div>
    """
  end

  attr :pending_email, :string, required: true
  attr :email_change_sent_at, :any, default: nil
  attr :myself, :any, required: true

  defp pending_email_notice(assigns) do
    ~H"""
    <div class="bg-amber-50 border border-amber-200 rounded-token-xl p-4 mt-4">
      <h4 class="text-token-sm font-bold text-amber-800">
        {dgettext("dashboard_profile", "Email Change Pending")}
      </h4>
      <div class="mt-2 text-token-sm text-amber-700">
        <p>
          {dgettext("dashboard_profile", "A verification email has been sent to")}
          <strong>{@pending_email}</strong>
        </p>
        <p :if={@email_change_sent_at} class="mt-1 text-token-xs text-amber-600">
          {dgettext("dashboard_profile", "Sent %{time}",
            time: format_relative_time(@email_change_sent_at)
          )}
        </p>
      </div>
      <div class="mt-3">
        <button
          type="button"
          phx-click="cancel_email_change"
          phx-target={@myself}
          class="text-token-sm font-bold text-amber-600 hover:text-amber-500"
        >
          {dgettext("dashboard_profile", "Cancel email change")}
        </button>
      </div>
    </div>
    """
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime)

    cond do
      diff < 60 -> dgettext("dashboard_profile", "just now")
      diff < 3600 -> unit_ago(div(diff, 60), :minute)
      diff < 86_400 -> unit_ago(div(diff, 3600), :hour)
      true -> unit_ago(div(diff, 86_400), :day)
    end
  end

  defp unit_ago(n, :minute),
    do: dngettext("dashboard_profile", "%{count} minute ago", "%{count} minutes ago", n)

  defp unit_ago(n, :hour),
    do: dngettext("dashboard_profile", "%{count} hour ago", "%{count} hours ago", n)

  defp unit_ago(n, :day),
    do: dngettext("dashboard_profile", "%{count} day ago", "%{count} days ago", n)
end
