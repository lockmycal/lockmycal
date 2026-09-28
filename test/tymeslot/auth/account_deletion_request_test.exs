defmodule Tymeslot.Auth.AccountDeletionRequestTest do
  @moduledoc """
  The synchronous half of account deletion: `Auth.request_account_deletion/2`
  blocks the account at once and hands the work to the background worker,
  and `Auth.verify_deletion_confirmation/2` checks what the user typed in the
  confirmation dialog.
  """

  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :auth

  alias Tymeslot.Auth
  alias Tymeslot.Auth.UserSessionQueries
  alias Tymeslot.Profiles
  alias Tymeslot.Security.Token
  alias Tymeslot.Workers.AccountDeletionWorker
  alias TymeslotWeb.Endpoint

  describe "request_account_deletion/2" do
    test "disables the account, marks it and enqueues the worker with the actor" do
      user = insert(:user)

      assert {:ok, requested} = Auth.request_account_deletion(user, :self)
      assert requested.deletion_requested_at
      assert requested.disabled_at

      assert_enqueued(
        worker: AccountDeletionWorker,
        args: %{"user_id" => user.id, "step" => "prepare", "actor" => "self"}
      )
    end

    test "records the admin who asked for it" do
      admin = insert(:user, is_admin: true)
      user = insert(:user)

      assert {:ok, _requested} = Auth.request_account_deletion(user, {:admin, admin.id})

      assert_enqueued(
        worker: AccountDeletionWorker,
        args: %{"user_id" => user.id, "actor" => "admin", "actor_user_id" => admin.id}
      )
    end

    test "revokes sessions and disconnects live sockets" do
      user = insert(:user)
      session = insert(:user_session, user: user)
      Endpoint.subscribe("users_sessions:#{Base.url_encode64(Token.hash_token(session.token))}")

      assert {:ok, _requested} = Auth.request_account_deletion(user, :self)

      assert [] == UserSessionQueries.list_user_session_token_hashes(user.id)
      assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    end

    test "is idempotent" do
      user = insert(:user)

      assert {:ok, first} = Auth.request_account_deletion(user, :self)
      assert {:ok, second} = Auth.request_account_deletion(user, :self)
      assert first.deletion_requested_at == second.deletion_requested_at

      assert [_only_one] = all_enqueued(worker: AccountDeletionWorker)
    end

    test "refuses the last admin and changes nothing" do
      admin = insert(:user, is_admin: true)

      assert {:error, :last_admin} = Auth.request_account_deletion(admin, :self)

      reloaded = Repo.reload!(admin)
      refute reloaded.deletion_requested_at
      refute reloaded.disabled_at
      refute_enqueued(worker: AccountDeletionWorker)
    end

    test "an admin already scheduled for deletion does not count towards the last-admin guard" do
      first = insert(:user, is_admin: true)
      second = insert(:user, is_admin: true)

      assert {:ok, _requested} = Auth.request_account_deletion(first, :self)
      assert {:error, :last_admin} = Auth.request_account_deletion(second, :self)
    end

    test "a scheduled account cannot be re-enabled" do
      admin = insert(:user, is_admin: true)
      user = insert(:user)
      {:ok, _requested} = Auth.request_account_deletion(user, {:admin, admin.id})

      assert {:error, :deletion_pending} = Auth.enable_account(admin, user.id)
    end

    test "the organiser's booking page stops resolving" do
      user = insert(:user)
      insert(:profile, user: user, username: "leaving-host")

      assert {:ok, _context} = Profiles.resolve_organizer_context("leaving-host")
      {:ok, _requested} = Auth.request_account_deletion(user, :self)

      assert {:error, :profile_not_found} = Profiles.resolve_organizer_context("leaving-host")
    end
  end

  describe "verify_deletion_confirmation/2" do
    test "an account with a password must give its current password" do
      user = insert(:user)

      assert Auth.deletion_confirms_with_password?(user)

      assert :ok =
               Auth.verify_deletion_confirmation(user, %{"current_password" => "Password123!"})

      assert {:error, :invalid_password} =
               Auth.verify_deletion_confirmation(user, %{"current_password" => "wrong"})

      assert {:error, :invalid_password} = Auth.verify_deletion_confirmation(user, %{})
    end

    test "an account without a password confirms by typing its email" do
      user =
        insert(:user, password_hash: nil, provider: "google", email: "Oauth.User@example.com")

      refute Auth.deletion_confirms_with_password?(user)

      assert :ok =
               Auth.verify_deletion_confirmation(user, %{
                 "email_confirmation" => "  oauth.user@EXAMPLE.com "
               })

      assert {:error, :email_mismatch} =
               Auth.verify_deletion_confirmation(user, %{
                 "email_confirmation" => "someone@else.com"
               })

      assert {:error, :email_mismatch} =
               Auth.verify_deletion_confirmation(user, %{"current_password" => "anything"})
    end
  end
end
