defmodule TymeslotWeb.AuthLiveMoreTest do
  use TymeslotWeb.LiveCase, async: false
  @moduletag :auth

  alias Tymeslot.Auth
  import Tymeslot.Factory

  describe "verify-email page" do
    test "shows the address the verification email was sent to", %{conn: conn} do
      user = insert(:unverified_user)

      conn =
        init_test_session(conn, %{
          "unverified_user_id" => user.id,
          "unverified_user_email" => user.email,
          "unverified_session_timestamp" => DateTime.to_unix(DateTime.utc_now())
        })

      {:ok, _view, html} = live(conn, ~p"/auth/verify-email")

      assert html =~ "Sent to"
      assert html =~ user.email
    end
  end

  describe "social sign-in buttons" do
    test "offer exactly the enabled providers, by display name", %{conn: conn} do
      social_auth = Application.get_env(:tymeslot, :social_auth, [])

      Application.put_env(
        :tymeslot,
        :social_auth,
        Keyword.merge(social_auth,
          google_enabled: false,
          github_enabled: true,
          oauth_enabled: true
        )
      )

      on_exit(fn -> Application.put_env(:tymeslot, :social_auth, social_auth) end)

      {:ok, view, _html} = live(conn, ~p"/auth/login")

      assert has_element?(view, ~s(a.btn-oauth[href="/auth/github"]), "GitHub")
      assert has_element?(view, ~s(a.btn-oauth[href="/auth/oauth"]), "SSO")
      refute has_element?(view, ~s(a.btn-oauth[href="/auth/google"]))
    end

    test "name the SSO provider when its configuration carries a name", %{conn: conn} do
      social_auth = Application.get_env(:tymeslot, :social_auth, [])
      oauth_provider = Application.get_env(:tymeslot, :oauth_provider, [])

      Application.put_env(:tymeslot, :social_auth, Keyword.put(social_auth, :oauth_enabled, true))

      Application.put_env(
        :tymeslot,
        :oauth_provider,
        Keyword.put(oauth_provider, :name, "Beaver Cloud")
      )

      on_exit(fn ->
        Application.put_env(:tymeslot, :social_auth, social_auth)
        Application.put_env(:tymeslot, :oauth_provider, oauth_provider)
      end)

      {:ok, view, _html} = live(conn, ~p"/auth/login")

      assert has_element?(view, ~s(a.btn-oauth[href="/auth/oauth"]), "Beaver Cloud")
      refute has_element?(view, ~s(a.btn-oauth[href="/auth/oauth"]), "SSO")
    end
  end

  describe "OAuth Completion" do
    test "renders complete registration form with session data", %{conn: conn} do
      conn =
        init_test_session(conn, %{
          "pending_oauth_registration" => %{
            provider: "github",
            email: "oauth@example.com",
            name: nil,
            email_from_provider: true,
            provider_uid: "12345",
            github_user_id: "12345",
            google_user_id: nil
          }
        })

      {:ok, view, html} = live(conn, ~p"/auth/complete-registration")

      assert has_element?(view, "#complete-registration-form")
      assert html =~ "oauth@example.com"
    end

    test "successful OAuth completion", %{conn: conn} do
      social_auth = Application.get_env(:tymeslot, :social_auth, [])

      Application.put_env(
        :tymeslot,
        :social_auth,
        Keyword.put(social_auth, :github_enabled, true)
      )

      on_exit(fn -> Application.put_env(:tymeslot, :social_auth, social_auth) end)

      conn =
        init_test_session(conn, %{
          "pending_oauth_registration" => %{
            provider: "github",
            email: "oauth_new@example.com",
            name: nil,
            email_from_provider: true,
            provider_uid: "gh_new_123",
            created_at: System.system_time(:second)
          }
        })

      {:ok, view, _html} = live(conn, ~p"/auth/complete-registration")

      form =
        form(view, "#complete-registration-form", %{
          "profile" => %{"full_name" => "OAuth New User"},
          "auth" => %{"terms_accepted" => "true"}
        })

      conn = submit_form(form, conn)
      assert redirected_to(conn) == "/dashboard"

      # Verify user was created
      assert user = Auth.get_user_by_email("oauth_new@example.com")
      assert user.github_user_id == "gh_new_123"
    end
  end

  describe "locale" do
    test "connected mount keeps a non-default session locale", %{conn: conn} do
      # The initial GET (still in the test process) runs LocalePlug, which
      # accepts the query param and persists it to the session. Connecting
      # the LiveView spawns a separate process — only the :auth live_session's
      # own on_mount locale hook can carry that session locale into it.
      {:ok, view, _html} = live(conn, "/auth/login?locale=de")

      # "Welcome Back!" only renders in German as "Willkommen zurück!" if the
      # connected LiveView process's own Gettext locale was set from the
      # session, not left on the process default ("en").
      assert render(view) =~ "Willkommen zurück!"
    end
  end
end
