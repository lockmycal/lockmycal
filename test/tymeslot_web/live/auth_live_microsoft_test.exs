defmodule TymeslotWeb.AuthLiveMicrosoftTest do
  @moduledoc """
  The auth pages' Microsoft sign-in: its button, and the complete-registration
  form prefilled with the address Microsoft suggested (never trusted, so it
  is still proved by email). Kept out of `AuthLiveTest`, which is already
  past the large-module line cap.
  """

  use TymeslotWeb.LiveCase, async: false
  @moduletag :auth

  test "the login page offers Microsoft, with its logo, once it is enabled", %{conn: conn} do
    social_auth = Application.get_env(:tymeslot, :social_auth, [])

    Application.put_env(
      :tymeslot,
      :social_auth,
      Keyword.put(social_auth, :microsoft_enabled, true)
    )

    on_exit(fn -> Application.put_env(:tymeslot, :social_auth, social_auth) end)

    {:ok, view, _html} = live(conn, ~p"/auth/login")

    assert has_element?(view, ~s(a.btn-oauth[href="/auth/microsoft"]), "Microsoft")
    assert has_element?(view, ~s(a.btn-oauth[href="/auth/microsoft"] img[src*="oauth/microsoft"]))
  end

  test "the login page has no Microsoft button while it is disabled", %{conn: conn} do
    social_auth = Application.get_env(:tymeslot, :social_auth, [])

    Application.put_env(
      :tymeslot,
      :social_auth,
      Keyword.put(social_auth, :microsoft_enabled, false)
    )

    on_exit(fn -> Application.put_env(:tymeslot, :social_auth, social_auth) end)

    {:ok, view, _html} = live(conn, ~p"/auth/login")

    refute has_element?(view, ~s(a[href="/auth/microsoft"]))
  end

  test "complete registration prefills the email Microsoft suggested", %{conn: conn} do
    conn =
      init_test_session(conn, %{
        "pending_oauth_registration" => %{
          provider: "microsoft",
          email: "",
          suggested_email: "someone@contoso.example",
          name: nil,
          email_from_provider: false,
          provider_uid: "ms-sub-1"
        }
      })

    {:ok, view, _html} = live(conn, ~p"/auth/complete-registration")

    assert has_element?(
             view,
             ~s(#complete-registration-form input[type="email"][name="auth[email]"][value="someone@contoso.example"])
           )
  end
end
