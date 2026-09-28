defmodule Tymeslot.Integrations.AccessRevocationTest do
  @moduledoc """
  Revoking a deleted user's OAuth grants at Google and Zoom — once per
  provider account, and never for an account another user still relies on.
  """

  use Tymeslot.DataCase, async: false

  @moduletag :integrations
  @moduletag :auth

  import Mox

  alias Tymeslot.Integrations.AccessRevocation
  alias Tymeslot.Security.Encryption

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:tymeslot, :zoom_oauth)

    Application.put_env(:tymeslot, :zoom_oauth,
      client_id: "zoom-client",
      client_secret: "zoom-secret"
    )

    on_exit(fn ->
      if original,
        do: Application.put_env(:tymeslot, :zoom_oauth, original),
        else: Application.delete_env(:tymeslot, :zoom_oauth)
    end)

    {:ok, user: insert(:user)}
  end

  defp google_calendar(user, account_id, refresh_token) do
    insert(:calendar_integration,
      user: user,
      provider: "google",
      provider_account_id: account_id,
      refresh_token_encrypted: Encryption.encrypt(refresh_token),
      access_token_encrypted: Encryption.encrypt("google-access")
    )
  end

  test "revokes a Google grant once for all integrations on the account", %{user: user} do
    google_calendar(user, "google-acct-1", "google-refresh")

    insert(:video_integration,
      user: user,
      provider: "google_meet",
      provider_account_id: "google-acct-1"
    )

    expect(Tymeslot.HTTPClientMock, :post, 1, fn url, body, _headers, _opts ->
      assert url == "https://oauth2.googleapis.com/revoke"
      assert URI.decode_query(body) == %{"token" => "google-refresh"}
      {:ok, %{status: 200, body: ""}}
    end)

    assert %{revoked: 1, skipped: 0, failed: 0} = AccessRevocation.revoke_for_user(user.id)
  end

  test "treats an already-revoked Google token as revoked", %{user: user} do
    google_calendar(user, "google-acct-2", "stale-refresh")

    expect(Tymeslot.HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
      {:ok, %{status: 400, body: ~s({"error":"invalid_token"})}}
    end)

    assert %{revoked: 1} = AccessRevocation.revoke_for_user(user.id)
  end

  test "revokes a Zoom access token with the app's basic auth", %{user: user} do
    insert(:video_integration,
      user: user,
      provider: "zoom",
      provider_account_id: "zoom-acct-1",
      access_token_encrypted: Encryption.encrypt("zoom-access")
    )

    expect(Tymeslot.HTTPClientMock, :post, fn url, "", headers, _opts ->
      assert url == "https://zoom.us/oauth/revoke?token=zoom-access"
      expected = "Basic " <> Base.encode64("zoom-client:zoom-secret")
      assert {"Authorization", ^expected} = List.keyfind(headers, "Authorization", 0)
      {:ok, %{status: 200, body: %{"status" => "success"}}}
    end)

    assert %{revoked: 1} = AccessRevocation.revoke_for_user(user.id)
  end

  test "skips an account another user also connected", %{user: user} do
    google_calendar(user, "shared-google", "mine")
    google_calendar(insert(:user), "shared-google", "theirs")

    expect(Tymeslot.HTTPClientMock, :post, 0, fn _url, _body, _headers, _opts -> :unused end)

    assert %{revoked: 0, skipped: 1} = AccessRevocation.revoke_for_user(user.id)
  end

  test "does not call anything for Microsoft or CalDAV integrations", %{user: user} do
    insert(:calendar_integration, user: user, provider: "outlook")
    insert(:calendar_integration, user: user)
    insert(:video_integration, user: user, provider: "teams")

    expect(Tymeslot.HTTPClientMock, :post, 0, fn _url, _body, _headers, _opts -> :unused end)

    assert %{revoked: 0, skipped: 0, failed: 0} = AccessRevocation.revoke_for_user(user.id)
  end

  test "a provider error is counted, not raised", %{user: user} do
    google_calendar(user, "google-acct-3", "refresh")

    expect(Tymeslot.HTTPClientMock, :post, fn _url, _body, _headers, _opts ->
      {:ok, %{status: 503, body: ""}}
    end)

    assert %{failed: 1} = AccessRevocation.revoke_for_user(user.id)
  end
end
