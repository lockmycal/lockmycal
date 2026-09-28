defmodule Tymeslot.Auth.AccountStatusTest do
  use Tymeslot.DataCase, async: true

  @moduletag :auth

  alias Tymeslot.Auth.{AccountStatus, UserSessionQueries}

  describe "disable/2" do
    test "revokes the user's existing sessions" do
      admin = insert(:user, is_admin: true)
      target = insert(:user)
      token = "session_before_disable"
      expires_at = DateTime.add(DateTime.utc_now(), 24, :hour)
      {:ok, _session} = UserSessionQueries.create_session(target.id, token, expires_at)

      assert {:ok, disabled} = AccountStatus.disable(admin, target.id)
      assert disabled.disabled_at

      assert [] == UserSessionQueries.list_user_session_token_hashes(target.id)
      assert nil == UserSessionQueries.get_user_by_session_token(token)
    end

    test "leaves sessions intact when the disable is refused" do
      admin = insert(:user, is_admin: true)
      token = "last_admin_session"
      expires_at = DateTime.add(DateTime.utc_now(), 24, :hour)
      {:ok, _session} = UserSessionQueries.create_session(admin.id, token, expires_at)

      assert {:error, :last_admin} = AccountStatus.disable(admin, admin.id)
      assert %{id: id} = UserSessionQueries.get_user_by_session_token(token)
      assert id == admin.id
    end
  end
end
