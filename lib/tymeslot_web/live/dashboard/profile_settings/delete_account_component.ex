defmodule TymeslotWeb.Dashboard.ProfileSettings.DeleteAccountComponent do
  @moduledoc """
  "Danger zone" on the Profile page: lets the user permanently delete their own
  account and all its data, including meeting history.

  The confirmation dialog asks for the current password, or — for an account
  signed up through OAuth, which has none — for the account email. On success
  the form is submitted as a plain HTTP request (`phx-trigger-action`) to
  `TymeslotWeb.AccountDeletionController`, which checks it again, schedules the
  deletion and signs the user out. This component only checks the confirmation
  first, so a mistake is shown inline in the dialog.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Tymeslot.Auth
  alias Tymeslot.Meetings
  alias Tymeslot.Security.RateLimiter
  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Dashboard.ProfileSettings.AccountSecurityForms, as: Forms
  alias TymeslotWeb.Helpers.ClientIP

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     assign(socket,
       show: false,
       errors: %{},
       deleting: false,
       submit_to_server: false,
       upcoming_count: 0,
       microsoft_consent: false
     )}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    user = assigns.current_user

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:last_admin, Auth.last_admin?(user))
     |> assign(:with_password, Auth.deletion_confirms_with_password?(user))}
  end

  @impl Phoenix.LiveComponent
  def handle_event("show", _params, socket) do
    {:noreply,
     assign(socket,
       show: true,
       errors: %{},
       upcoming_count:
         Meetings.count_upcoming_active_for_organizer(socket.assigns.current_user.id),
       microsoft_consent: Auth.deletion_leaves_microsoft_consent?(socket.assigns.current_user)
     )}
  end

  def handle_event("hide", _params, socket) do
    {:noreply, assign(socket, show: false, errors: %{}, deleting: false)}
  end

  def handle_event("delete_account", %{"delete_account" => params}, socket) do
    user = socket.assigns.current_user

    with :ok <- RateLimiter.check_auth_rate_limit(user.email, ClientIP.get(socket)),
         :ok <- Auth.verify_deletion_confirmation(user, params),
         false <- Auth.last_admin?(user) do
      {:noreply, assign(socket, deleting: true, submit_to_server: true)}
    else
      true ->
        {:noreply, assign(socket, :errors, error_for(:last_admin))}

      {:error, :rate_limited, message} ->
        {:noreply, assign(socket, :errors, %{base: [message]})}

      {:error, reason} ->
        {:noreply, assign(socket, :errors, error_for(reason))}
    end
  end

  defp error_for(:invalid_password),
    do: %{current_password: [dgettext("dashboard_profile", "Current password is incorrect")]}

  defp error_for(:email_mismatch),
    do: %{
      email_confirmation: [
        dgettext("dashboard_profile", "This does not match your account email address")
      ]
    }

  defp error_for(:last_admin),
    do: %{base: [last_admin_message()]}

  defp last_admin_message do
    dgettext(
      "dashboard_profile",
      "You are the only admin. Promote another user to admin before deleting your account."
    )
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, :last_admin_message, last_admin_message())

    ~H"""
    <div id={@id} class="card-glass">
      <CoreComponents.subsection_header
        icon="hero-exclamation-triangle"
        title={dgettext("dashboard_profile", "Danger zone")}
        class="mb-3"
      />

      <div class="flex flex-col sm:flex-row sm:items-center gap-4 sm:justify-between">
        <div>
          <p class="text-token-sm font-bold text-neutral-900 dark:text-neutral-50">
            {dgettext("dashboard_profile", "Delete account")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_profile",
              "Permanently delete your account and all your data, including your meeting history. This cannot be undone."
            )}
          </p>
          <p
            :if={@last_admin}
            class="mt-2 text-token-sm font-medium text-red-600"
            data-testid="delete-account-last-admin"
          >
            {@last_admin_message}
          </p>
        </div>

        <CoreComponents.action_button
          id="delete-account-button"
          variant={:danger}
          disabled={@last_admin}
          phx-click={JS.push("show", target: @myself)}
          class="whitespace-nowrap"
        >
          {dgettext("dashboard_profile", "Delete account")}
        </CoreComponents.action_button>
      </div>

      <CoreComponents.modal
        id={"#{@id}-modal"}
        show={@show}
        on_cancel={JS.push("hide", target: @myself)}
        size={:medium}
      >
        <:header>
          <span class="text-2xl font-black text-neutral-900 dark:text-neutral-50 tracking-tight">
            {dgettext("dashboard_profile", "Delete account")}
          </span>
        </:header>

        <%!-- Only while open: the confirmation field must not sit in the page
             (hidden) for every visit to the settings page. --%>
        <div :if={@show} class="space-y-4">
          <p class="text-neutral-600 dark:text-neutral-300 font-medium leading-relaxed">
            {dgettext(
              "dashboard_profile",
              "This permanently deletes your account, your profile, meeting types, integrations and your whole meeting history. This cannot be undone."
            )}
          </p>

          <p
            :if={@upcoming_count > 0}
            class="text-token-sm font-medium text-red-600"
            data-testid="delete-account-upcoming"
          >
            {dngettext(
              "dashboard_profile",
              "Your %{count} upcoming meeting will be cancelled, its attendee notified and any payment refunded.",
              "Your %{count} upcoming meetings will be cancelled, their attendees notified and any payments refunded.",
              @upcoming_count,
              count: @upcoming_count
            )}
          </p>

          <p
            :if={@microsoft_consent}
            class="text-token-sm font-medium text-neutral-600 dark:text-neutral-300"
            data-testid="delete-account-microsoft"
          >
            {dgettext(
              "dashboard_profile",
              "Microsoft does not let us withdraw your consent for Tymeslot. To remove it, open myapps.microsoft.com and remove Tymeslot from your apps."
            )}
          </p>

          <.form
            for={%{}}
            as={:delete_account}
            id="delete-account-form"
            action={~p"/dashboard/settings/delete-account"}
            phx-submit="delete_account"
            phx-trigger-action={@submit_to_server}
            phx-target={@myself}
            class="space-y-4"
          >
            <CoreComponents.input
              :if={@with_password}
              name="delete_account[current_password]"
              autocomplete="current-password"
              type="password"
              label={dgettext("dashboard_profile", "Current Password")}
              placeholder={dgettext("dashboard_profile", "Enter your current password")}
              errors={Map.get(@errors, :current_password, [])}
              required
              icon="hero-lock-closed"
            />

            <CoreComponents.input
              :if={!@with_password}
              name="delete_account[email_confirmation]"
              type="text"
              label={
                dgettext("dashboard_profile", "Type %{email} to confirm", email: @current_user.email)
              }
              errors={Map.get(@errors, :email_confirmation, [])}
              required
              icon="hero-envelope"
            />

            <Forms.form_errors errors={Map.get(@errors, :base)} />
          </.form>
        </div>

        <:footer>
          <div class="flex justify-end gap-3">
            <CoreComponents.action_button
              variant={:secondary}
              disabled={@deleting}
              phx-click={JS.push("hide", target: @myself)}
            >
              {dgettext("dashboard_profile", "Cancel")}
            </CoreComponents.action_button>
            <CoreComponents.loading_button
              id="delete-account-confirm-button"
              type="submit"
              form="delete-account-form"
              variant={:danger}
              loading={@deleting}
              loading_text={dgettext("dashboard_profile", "Deleting...")}
            >
              {dgettext("dashboard_profile", "Permanently delete my account")}
            </CoreComponents.loading_button>
          </div>
        </:footer>
      </CoreComponents.modal>
    </div>
    """
  end
end
