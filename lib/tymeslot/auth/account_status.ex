defmodule Tymeslot.Auth.AccountStatus do
  @moduledoc """
  Domain logic for disabling/enabling a user account.

  This is the single entry point for blocking a user from logging in without
  deleting their account. Mirrors `Tymeslot.Auth.AdminRoles`'s structure and
  guards: the admin UI feature flag gate, and the last-admin guard so the
  install can never be locked out by disabling its only remaining admin.

  A disabled account is refused at login (password in
  `Tymeslot.Auth.Authentication.verify_user_password/3`, OAuth/OIDC in
  `Tymeslot.Auth.OAuth.FlowHandler`), its existing sessions are revoked, and
  any session token it still holds no longer resolves to a user. Otherwise the
  account is left intact — nothing else is deleted or anonymised.
  """

  alias Tymeslot.Auth.{AdminRoles, AdminUserQueries, Session, UserQueries, UserSchema}
  alias Tymeslot.Repo
  alias Tymeslot.Security.SecurityLogger

  @type actor :: %UserSchema{} | :cli

  @doc """
  Disables the user identified by `target_user_id`, blocking further logins
  and revoking all of their existing sessions.

  Idempotent: if the user is already disabled, returns `{:ok, user}` without
  writing to the database.

  Guard (skipped when actor is `:cli`):
    * Returns `{:error, :last_admin}` when the target is the only remaining
      admin user (checked inside a locked transaction to prevent races).

  Returns:
    * `{:ok, %UserSchema{}}` on success (or if already disabled)
    * `{:error, :admin_ui_disabled}` if the admin UI feature flag is off
    * `{:error, :not_found}` if no user has that ID
    * `{:error, :last_admin}` if the target is the only admin
    * `{:error, changeset}` if the database update fails
  """
  @spec disable(actor(), pos_integer()) ::
          {:ok, UserSchema.t()}
          | {:error, :not_found | :last_admin | :admin_ui_disabled | Ecto.Changeset.t()}
  def disable(actor, target_user_id) do
    with :ok <- ensure_admin_ui_enabled(),
         {:ok, user} <-
           Repo.transaction(fn -> disable_in_transaction(actor, target_user_id) end) do
      # Only after commit: disconnecting live sockets for a disable that later
      # rolled back would be wrong (see `Session.disconnect_session_hash/1`).
      Session.revoke_all_sessions(user.id)
      {:ok, user}
    end
  end

  @doc """
  Re-enables the user identified by `target_user_id`, restoring login access.

  Idempotent: if the user is already enabled, returns `{:ok, user}` without
  writing to the database.

  Returns:
    * `{:ok, %UserSchema{}}` on success (or if already enabled)
    * `{:error, :admin_ui_disabled}` if the admin UI feature flag is off
    * `{:error, :not_found}` if no user has that ID
    * `{:error, :deletion_pending}` if the account is scheduled for deletion —
      it stays disabled until the deletion has run
    * `{:error, changeset}` if the database update fails
  """
  @spec enable(actor(), pos_integer()) ::
          {:ok, UserSchema.t()}
          | {:error, :not_found | :deletion_pending | :admin_ui_disabled | Ecto.Changeset.t()}
  def enable(actor, target_user_id) do
    with :ok <- ensure_admin_ui_enabled() do
      Repo.transaction(fn ->
        case UserQueries.get_user(target_user_id) do
          {:error, :not_found} ->
            Repo.rollback(:not_found)

          {:ok, %UserSchema{deletion_requested_at: %DateTime{}}} ->
            Repo.rollback(:deletion_pending)

          {:ok, %UserSchema{disabled_at: nil} = target} ->
            target

          {:ok, target} ->
            case UserQueries.set_disabled(target, nil) do
              {:ok, updated} ->
                log_status_change(:enable, actor, updated.id)
                updated

              {:error, changeset} ->
                Repo.rollback(changeset)
            end
        end
      end)
    end
  end

  # --- Private helpers ---

  defp disable_in_transaction(actor, target_user_id) do
    # Lock all admin rows before counting so that concurrent disables cannot
    # race past the last-admin guard, same as `AdminRoles.demote/2`.
    AdminUserQueries.lock_admins()

    case UserQueries.get_user(target_user_id) do
      {:error, :not_found} ->
        Repo.rollback(:not_found)

      {:ok, target} ->
        apply_disable(actor, target)
    end
  end

  defp apply_disable(_actor, %UserSchema{disabled_at: disabled_at} = target)
       when disabled_at != nil do
    target
  end

  defp apply_disable(actor, target) do
    case check_last_admin(actor, target) do
      {:error, :last_admin} ->
        Repo.rollback(:last_admin)

      :ok ->
        case UserQueries.set_disabled(target, DateTime.utc_now(:second)) do
          {:ok, updated} ->
            log_status_change(:disable, actor, updated.id)
            updated

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
    end
  end

  defp ensure_admin_ui_enabled do
    if AdminRoles.admin_ui_enabled?() do
      :ok
    else
      {:error, :admin_ui_disabled}
    end
  end

  # CLI actor: skips the last-admin guard — same operator escape hatch as
  # `AdminRoles.demote/2`.
  defp check_last_admin(:cli, _target), do: :ok

  # Target is not an admin — no risk of stranding the install.
  defp check_last_admin(_actor, %UserSchema{is_admin: false}), do: :ok

  defp check_last_admin(_actor, %UserSchema{is_admin: true}) do
    if AdminUserQueries.count_admins() <= 1 do
      {:error, :last_admin}
    else
      :ok
    end
  end

  # Through `SecurityLogger` so the change is in the audit log as well as the
  # log line: `account_disabled` / `account_enabled`, about the target user,
  # caused by the acting admin (`nil` for the CLI).
  defp log_status_change(action, actor, target_user_id) do
    SecurityLogger.log_security_event("account_#{action}d", %{
      user_id: target_user_id,
      actor_user_id: actor_id(actor),
      additional_data: %{actor: actor_kind(actor)}
    })
  end

  defp actor_id(%UserSchema{id: id}), do: id
  defp actor_id(:cli), do: nil

  defp actor_kind(%UserSchema{}), do: "admin"
  defp actor_kind(:cli), do: "cli"
end
