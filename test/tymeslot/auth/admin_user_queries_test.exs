defmodule Tymeslot.Auth.AdminUserQueriesTest do
  @moduledoc false

  use Tymeslot.DataCase, async: true

  @moduletag :database
  @moduletag :queries

  alias Tymeslot.Auth.AdminUserQueries

  # `any_admin_uses_password_auth?/1` backs the lockout guard in
  # `Tymeslot.AppSettings.LockoutPolicy`: it must count only admins who can
  # actually pass `Tymeslot.Auth.Authentication.verify_user_password/2`'s
  # gate, or the guard can be talked into disabling the last working sign-in
  # path by an admin who merely has a password hash on file.
  describe "any_admin_uses_password_auth?/1" do
    test "true for an admin with a verified, non-OAuth password account" do
      insert(:user, is_admin: true, password_hash: "hash", verified_at: DateTime.utc_now())

      assert AdminUserQueries.any_admin_uses_password_auth?()
    end

    test "false for an unverified admin, even with a password hash set" do
      insert(:user, is_admin: true, password_hash: "hash", verified_at: nil)

      refute AdminUserQueries.any_admin_uses_password_auth?()
    end

    test "false for an OAuth-only admin, even with a leftover password hash" do
      insert(:user,
        is_admin: true,
        password_hash: "hash",
        verified_at: DateTime.utc_now(),
        provider: "google",
        google_user_id: "google-1"
      )

      refute AdminUserQueries.any_admin_uses_password_auth?()
    end

    test "false when no admin has a password hash at all" do
      insert(:user, is_admin: true, password_hash: nil, verified_at: DateTime.utc_now())

      refute AdminUserQueries.any_admin_uses_password_auth?()
    end
  end

  describe "count_signin_capable_admins_excluding/2" do
    test "counts a Microsoft admin only while Microsoft is a usable provider" do
      excluded = insert(:user, is_admin: true)

      insert(:user,
        is_admin: true,
        password_hash: nil,
        provider: "microsoft",
        microsoft_user_id: "ms-sub-1"
      )

      assert AdminUserQueries.count_signin_capable_admins_excluding(excluded.id, [:microsoft]) ==
               1

      assert AdminUserQueries.count_signin_capable_admins_excluding(excluded.id, [:google]) == 0
    end
  end

  describe "list_all_users/1 (admin Users table search)" do
    test "returns everyone when search is nil or blank" do
      insert(:user)
      insert(:user)

      assert length(AdminUserQueries.list_all_users(nil)) == 2
      assert length(AdminUserQueries.list_all_users("")) == 2
    end

    test "filters by a case-insensitive substring match on email" do
      match = insert(:user, email: "alice@example.com")
      insert(:user, email: "bob@example.com")

      assert [found] = AdminUserQueries.list_all_users("ALICE")
      assert found.id == match.id
    end

    test "filters by a substring match on the profile's display name or username" do
      match = insert(:user)
      insert(:profile, user: match, full_name: "Jane Doe", username: "janedoe")
      other = insert(:user)
      insert(:profile, user: other, full_name: "Someone Else", username: "someone")

      assert [found] = AdminUserQueries.list_all_users("jane")
      assert found.id == match.id

      assert [found_by_username] = AdminUserQueries.list_all_users("janedoe")
      assert found_by_username.id == match.id
    end

    test "escapes _ so it matches literally instead of as a LIKE any-character wildcard" do
      match = insert(:user, email: "a_b@example.com")
      # If "_" weren't escaped, the ILIKE pattern "%a_b%" would also match
      # this row (any single character in the "_" position) — proving the
      # search stayed a literal match rather than an accidental wildcard.
      insert(:user, email: "aXb@example.com")

      assert [found] = AdminUserQueries.list_all_users("a_b")
      assert found.id == match.id
    end

    test "escapes % so it matches literally instead of as a LIKE any-substring wildcard" do
      match = insert(:user, email: "a%b@example.com")
      # If "%" weren't escaped, the ILIKE pattern "%a%b%" would also match
      # this row (any substring, including none, in the "%" position).
      insert(:user, email: "aXXXb@example.com")

      assert [found] = AdminUserQueries.list_all_users("a%b")
      assert found.id == match.id
    end
  end
end
