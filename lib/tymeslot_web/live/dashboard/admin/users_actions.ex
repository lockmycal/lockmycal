defmodule TymeslotWeb.Dashboard.Admin.UsersActions do
  @moduledoc """
  Users-tab event logic for `TymeslotWeb.Dashboard.Admin.HubComponent` — the
  promote/demote/delete/disable/enable flows, their per-action guards, and
  the pending-confirmation state they share. Split out of `HubComponent`
  purely to stay under the project's per-module line-count budget; every
  public function here takes the LiveComponent's `socket` and returns
  `{:noreply, socket}`, same contract as if it were still defined there.

  Calls back into `HubComponent.load_users_data/2` to refresh the users list
  after a write, since that reload is tied to the component's own assign
  structure (batches each user's Connect country alongside the list).
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2]

  alias Tymeslot.Auth
  alias Tymeslot.Auth.UserSchema
  alias TymeslotWeb.Dashboard.Admin.HubComponent
  alias TymeslotWeb.Live.Shared.Flash

  @doc "Opens the confirmation card for a promote/demote/delete/disable/enable action."
  @spec open_pending_action(atom(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def open_pending_action(kind, %{"id" => id, "email" => email}, socket) do
    case parse_user_id(id) do
      {:ok, user_id} ->
        {:noreply, assign(socket, :pending_action, %{kind: kind, id: user_id, email: email})}

      :error ->
        {:noreply,
         Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Invalid user id."))}
    end
  end

  def open_pending_action(_kind, _params, socket) do
    {:noreply, Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Invalid request."))}
  end

  @doc "Parses `id` and calls `fun.(user_id, socket)`, or flashes on a bad id."
  @spec with_user_id(String.t(), Phoenix.LiveView.Socket.t(), (integer(),
                                                               Phoenix.LiveView.Socket.t() ->
                                                                 {:noreply,
                                                                  Phoenix.LiveView.Socket.t()})) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def with_user_id(id, socket, fun) do
    case parse_user_id(id) do
      {:ok, user_id} ->
        fun.(user_id, socket)

      :error ->
        {:noreply,
         Flash.put_flash(socket, :error, dgettext("dashboard_admin", "Invalid user id."))}
    end
  end

  defp parse_user_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {user_id, ""} when user_id > 0 -> {:ok, user_id}
      _other -> :error
    end
  end

  defp parse_user_id(_id), do: :error

  @spec handle_promote(integer(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_promote(user_id, socket) do
    case Auth.promote_admin(socket.assigns.current_user, user_id) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> clear_pending_action()
         |> Flash.put_flash(:info, dgettext("dashboard_admin", "User promoted to admin."))
         |> HubComponent.load_users_data(socket.assigns.user_search)}

      {:error, reason} ->
        {:noreply,
         socket
         |> clear_pending_action()
         |> Flash.put_flash(:error, role_change_error_message(:promote, reason))}
    end
  end

  @spec handle_demote(integer(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_demote(user_id, socket) do
    self_demote? = user_id == socket.assigns.current_user.id

    case Auth.demote_admin(socket.assigns.current_user, user_id) do
      {:ok, _user} when self_demote? ->
        # Self-demote: navigate to /dashboard so the fresh mount re-runs the
        # auth hooks with the now-demoted user, dropping the admin menu entry
        # and blocking re-entry into the admin actions. No accompanying
        # flash — same trade-off as `HubComponent.with_admin/2`. A plain
        # string, not `~p`: this module isn't a LiveView/-Component, so the
        # verified-routes sigil isn't available without extra plumbing for
        # one stable, already-hardcoded-elsewhere route.
        {:noreply, push_navigate(clear_pending_action(socket), to: "/dashboard")}

      {:ok, _user} ->
        {:noreply,
         socket
         |> clear_pending_action()
         |> Flash.put_flash(:info, dgettext("dashboard_admin", "User demoted from admin."))
         |> HubComponent.load_users_data(socket.assigns.user_search)}

      {:error, reason} ->
        {:noreply,
         socket
         |> clear_pending_action()
         |> Flash.put_flash(:error, role_change_error_message(:demote, reason))}
    end
  end

  defp role_change_error_message(_action, :not_found),
    do: dgettext("dashboard_admin", "User not found.")

  defp role_change_error_message(_action, :forbidden),
    do: dgettext("dashboard_admin", "Admin access required.")

  defp role_change_error_message(_action, :admin_ui_disabled),
    do: dgettext("dashboard_admin", "Admin UI is disabled.")

  defp role_change_error_message(:demote, :last_admin),
    do: dgettext("dashboard_admin", "Cannot demote the last admin. Promote someone else first.")

  defp role_change_error_message(:promote, %Ecto.Changeset{}),
    do: dgettext("dashboard_admin", "Could not promote user.")

  defp role_change_error_message(:demote, %Ecto.Changeset{}),
    do: dgettext("dashboard_admin", "Could not demote user.")

  @spec handle_delete(integer(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_delete(user_id, socket) do
    case delete_guard(socket, user_id) do
      {:error, reason} ->
        {:noreply,
         socket
         |> clear_pending_action()
         |> Flash.put_flash(:error, user_action_error_message(:delete, reason))}

      {:ok, target} ->
        case Auth.request_account_deletion(target, {:admin, socket.assigns.current_user.id}) do
          {:ok, _user} ->
            {:noreply,
             socket
             |> clear_pending_action()
             |> Flash.put_flash(
               :info,
               dgettext(
                 "dashboard_admin",
                 "Account deletion scheduled. The user's upcoming meetings are being cancelled and their data will be deleted shortly."
               )
             )
             |> HubComponent.load_users_data(socket.assigns.user_search)}

          {:error, reason} ->
            {:noreply,
             socket
             |> clear_pending_action()
             |> Flash.put_flash(:error, user_action_error_message(:delete, reason))}
        end
    end
  end

  # `Auth.request_account_deletion/2` enforces the last-admin guard itself
  # (it also backs self-service deletion). Deleting yourself is refused here
  # only: an admin deletes their own account from their settings page, where
  # it is confirmed with their password, not from the users table.
  defp delete_guard(socket, user_id) do
    if user_id == socket.assigns.current_user.id do
      {:error, :cannot_delete_self}
    else
      case Auth.get_user(user_id) do
        {:error, :not_found} ->
          {:error, :not_found}

        {:ok, %UserSchema{is_admin: true} = target} ->
          if socket.assigns.admin_count <= 1 do
            {:error, :last_admin}
          else
            {:ok, target}
          end

        {:ok, target} ->
          {:ok, target}
      end
    end
  end

  @spec handle_disable(integer(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_disable(user_id, socket) do
    if user_id == socket.assigns.current_user.id do
      {:noreply,
       socket
       |> clear_pending_action()
       |> Flash.put_flash(
         :error,
         dgettext("dashboard_admin", "You cannot disable your own account here.")
       )}
    else
      case Auth.disable_account(socket.assigns.current_user, user_id) do
        {:ok, _user} ->
          {:noreply,
           socket
           |> clear_pending_action()
           |> Flash.put_flash(:info, dgettext("dashboard_admin", "User disabled."))
           |> HubComponent.load_users_data(socket.assigns.user_search)}

        {:error, reason} ->
          {:noreply,
           socket
           |> clear_pending_action()
           |> Flash.put_flash(:error, user_action_error_message(:disable, reason))}
      end
    end
  end

  @spec handle_enable(integer(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_enable(user_id, socket) do
    case Auth.enable_account(socket.assigns.current_user, user_id) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> clear_pending_action()
         |> Flash.put_flash(:info, dgettext("dashboard_admin", "User enabled."))
         |> HubComponent.load_users_data(socket.assigns.user_search)}

      {:error, reason} ->
        {:noreply,
         socket
         |> clear_pending_action()
         |> Flash.put_flash(:error, user_action_error_message(:enable, reason))}
    end
  end

  defp user_action_error_message(_action, :not_found),
    do: dgettext("dashboard_admin", "User not found.")

  defp user_action_error_message(_action, :admin_ui_disabled),
    do: dgettext("dashboard_admin", "Admin UI is disabled.")

  defp user_action_error_message(:delete, :cannot_delete_self),
    do: dgettext("dashboard_admin", "You cannot delete your own account here.")

  defp user_action_error_message(:delete, :last_admin),
    do: dgettext("dashboard_admin", "Cannot delete the last admin. Promote someone else first.")

  defp user_action_error_message(:delete, _other),
    do: dgettext("dashboard_admin", "Could not delete user.")

  defp user_action_error_message(:disable, :last_admin),
    do: dgettext("dashboard_admin", "Cannot disable the last admin. Promote someone else first.")

  defp user_action_error_message(:disable, _other),
    do: dgettext("dashboard_admin", "Could not disable user.")

  defp user_action_error_message(:enable, :deletion_pending),
    do:
      dgettext("dashboard_admin", "This account is scheduled for deletion and cannot be enabled.")

  defp user_action_error_message(:enable, _other),
    do: dgettext("dashboard_admin", "Could not enable user.")

  @doc "Clears any in-flight promote/demote/delete/disable/enable confirmation."
  @spec clear_pending_action(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def clear_pending_action(socket) do
    socket
    |> assign(:pending_action, nil)
    |> assign(:pending_action_submitting, false)
  end
end
