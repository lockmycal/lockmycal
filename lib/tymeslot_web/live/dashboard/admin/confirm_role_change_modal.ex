defmodule TymeslotWeb.Dashboard.Admin.ConfirmRoleChangeModal do
  @moduledoc """
  Confirmation modal for promoting a user to admin or demoting an admin.
  Replaces the browser-native `data-confirm` dialog so the admin flow stays
  inside the design system.

  Rendered inside `TymeslotWeb.Dashboard.Admin.HubComponent` — every
  `JS.push` targets `@target` (the hub's `@myself`) so events reach the
  hub's own `handle_event/3` rather than the parent LiveView.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS

  attr :action, :atom, required: true, values: [:promote, :demote]
  attr :user, :map, required: true, doc: "Map with :id and :email"
  attr :self?, :boolean, default: false, doc: "True when the target is the current admin"
  attr :submitting, :boolean, default: false
  attr :target, :any, required: true

  @spec confirm_role_change_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def confirm_role_change_modal(assigns) do
    ~H"""
    <.modal
      id="confirm-role-change-modal"
      show={true}
      on_cancel={JS.push("cancel_pending_action", target: @target)}
      size={:xsmall}
    >
      <:header>{header_label(@action, @self?)}</:header>

      <p
        :if={@action == :promote}
        class="text-base text-neutral-700 dark:text-neutral-200 font-medium leading-relaxed"
      >
        {dgettext("dashboard_admin", "Promote %{email} to admin?", email: @user.email)}
      </p>
      <p
        :if={@action == :demote and @self?}
        class="text-base text-neutral-700 dark:text-neutral-200 font-medium leading-relaxed"
      >
        {dgettext("dashboard_admin", "Demote yourself from admin?")}
      </p>
      <p
        :if={@action == :demote and not @self?}
        class="text-base text-neutral-700 dark:text-neutral-200 font-medium leading-relaxed"
      >
        {dgettext("dashboard_admin", "Demote %{email} from admin?", email: @user.email)}
      </p>

      <p :if={@action == :promote} class="mt-3 text-sm text-neutral-500">
        {dgettext("dashboard_admin", "They will gain access to admin settings and user management.")}
      </p>
      <p :if={@action == :demote and @self?} class="mt-3 text-sm text-amber-600 font-medium">
        {dgettext(
          "dashboard_admin",
          "You will lose access to admin settings and user management, and be returned to your dashboard."
        )}
      </p>
      <p :if={@action == :demote and not @self?} class="mt-3 text-sm text-amber-600 font-medium">
        {dgettext("dashboard_admin", "They will lose access to admin settings and user management.")}
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
            id="confirm-role-change-confirm-button"
            variant={confirm_variant(@action)}
            loading={@submitting}
            loading_text={loading_label(@action)}
            phx-click={JS.push(confirm_event(@action), target: @target)}
            phx-value-id={@user.id}
          >
            {confirm_label(@action, @self?)}
          </.loading_button>
        </div>
      </:footer>
    </.modal>
    """
  end

  defp header_label(:promote, _self?), do: dgettext("dashboard_admin", "Promote user to admin")
  defp header_label(:demote, true), do: dgettext("dashboard_admin", "Demote yourself")
  defp header_label(:demote, false), do: dgettext("dashboard_admin", "Demote admin")

  defp confirm_variant(:promote), do: :primary
  defp confirm_variant(:demote), do: :danger

  defp confirm_event(:promote), do: "promote_user"
  defp confirm_event(:demote), do: "demote_user"

  defp confirm_label(:promote, _self?), do: dgettext("dashboard_admin", "Promote")
  defp confirm_label(:demote, true), do: dgettext("dashboard_admin", "Demote me")
  defp confirm_label(:demote, false), do: dgettext("dashboard_admin", "Demote")

  defp loading_label(:promote), do: dgettext("dashboard_admin", "Promoting...")
  defp loading_label(:demote), do: dgettext("dashboard_admin", "Demoting...")
end
