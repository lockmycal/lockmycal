defmodule TymeslotWeb.Dashboard.Admin.ConfirmUserActionModal do
  @moduledoc """
  Confirmation modal for deleting a user or disabling/enabling their account.
  Kept separate from `ConfirmRoleChangeModal` (rather than folded into it) so
  that component's DOM ids and existing tests are untouched.

  Rendered inside `TymeslotWeb.Dashboard.Admin.HubComponent` — every
  `JS.push` targets `@target` (the hub's `@myself`) so events reach the
  hub's own `handle_event/3` rather than the parent LiveView.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS

  attr :action, :atom, required: true, values: [:delete, :disable, :enable]
  attr :user, :map, required: true, doc: "Map with :id and :email"
  attr :submitting, :boolean, default: false
  attr :target, :any, required: true

  @spec confirm_user_action_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def confirm_user_action_modal(assigns) do
    ~H"""
    <.modal
      id="confirm-user-action-modal"
      show={true}
      on_cancel={JS.push("cancel_pending_action", target: @target)}
      size={:xsmall}
    >
      <:header>{header_label(@action)}</:header>

      <p class="text-base text-neutral-700 dark:text-neutral-200 font-medium leading-relaxed">
        {confirm_question(@action, @user.email)}
      </p>

      <p :if={@action == :delete} class="mt-3 text-sm text-red-600 font-medium">
        {dgettext(
          "dashboard_admin",
          "This permanently deletes their account and all their data, including past meetings, and cannot be undone."
        )}
      </p>
      <p :if={@action == :delete} class="mt-2 text-sm text-neutral-600 dark:text-neutral-300">
        {dgettext(
          "dashboard_admin",
          "They are signed out at once. Their upcoming meetings are cancelled, attendees are notified and paid bookings refunded, then the data is deleted in the background."
        )}
      </p>
      <p :if={@action == :disable} class="mt-3 text-sm text-amber-600 font-medium">
        {dgettext("dashboard_admin", "They will be signed out and unable to log back in.")}
      </p>

      <:footer>
        <div class="flex gap-3 justify-end">
          <.action_button
            variant={:secondary}
            disabled={@submitting}
            phx-click={JS.push("cancel_pending_action", target: @target)}
          >
            {dgettext("dashboard_admin", "Cancel")}
          </.action_button>
          <.loading_button
            id="confirm-user-action-confirm-button"
            variant={confirm_variant(@action)}
            loading={@submitting}
            loading_text={loading_label(@action)}
            phx-click={JS.push(confirm_event(@action), target: @target)}
            phx-value-id={@user.id}
          >
            {confirm_label(@action)}
          </.loading_button>
        </div>
      </:footer>
    </.modal>
    """
  end

  defp header_label(:delete), do: dgettext("dashboard_admin", "Delete user")
  defp header_label(:disable), do: dgettext("dashboard_admin", "Disable user")
  defp header_label(:enable), do: dgettext("dashboard_admin", "Enable user")

  defp confirm_question(:delete, email),
    do: dgettext("dashboard_admin", "Permanently delete %{email}?", email: email)

  defp confirm_question(:disable, email),
    do: dgettext("dashboard_admin", "Disable %{email}?", email: email)

  defp confirm_question(:enable, email),
    do: dgettext("dashboard_admin", "Enable %{email}?", email: email)

  defp confirm_variant(:delete), do: :danger
  defp confirm_variant(:disable), do: :danger
  defp confirm_variant(:enable), do: :primary

  defp confirm_event(:delete), do: "delete_user"
  defp confirm_event(:disable), do: "disable_user"
  defp confirm_event(:enable), do: "enable_user"

  defp confirm_label(:delete), do: dgettext("dashboard_admin", "Delete")
  defp confirm_label(:disable), do: dgettext("dashboard_admin", "Disable")
  defp confirm_label(:enable), do: dgettext("dashboard_admin", "Enable")

  defp loading_label(:delete), do: dgettext("dashboard_admin", "Deleting...")
  defp loading_label(:disable), do: dgettext("dashboard_admin", "Disabling...")
  defp loading_label(:enable), do: dgettext("dashboard_admin", "Enabling...")
end
