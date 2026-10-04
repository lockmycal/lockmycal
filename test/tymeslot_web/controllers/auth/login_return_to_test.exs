defmodule TymeslotWeb.LoginReturnToTest do
  @moduledoc """
  Signing in from the booking form (`?return_to=`) lands back on that form,
  through the password form and through an OAuth provider round trip alike;
  anything but a same-origin path is ignored.
  """
  use TymeslotWeb.ConnCase, async: false

  @moduletag :auth

  import Tymeslot.Factory, only: [insert: 2]
  import Tymeslot.Test.OAuthProviderStub

  alias Tymeslot.Security.RateLimiter

  @return_to "/host/30min/book?date=2026-10-05&time=10:00 AM"

  setup :setup_providers

  setup do
    RateLimiter.clear_all()
    :ok
  end

  defp oauth_sign_in(conn, start_params) do
    start = get(conn, "/auth/github", start_params)
    %{"state" => state} = start |> redirected_to(302) |> authorise_params()

    start
    |> recycle()
    |> get("/auth/github/callback", %{"code" => "provider-code", "state" => state})
  end

  describe "login page" do
    test "carries return_to into the password form and the provider buttons", %{conn: conn} do
      html = conn |> get("/auth/login", %{"return_to" => @return_to}) |> html_response(200)

      assert html =~ ~s(name="redirect_to")
      assert html =~ "/auth/github?return_to=" <> URI.encode_www_form(@return_to)
    end

    test "ignores a return_to that leaves the site", %{conn: conn} do
      html =
        conn |> get("/auth/login", %{"return_to" => "//evil.com/steal"}) |> html_response(200)

      refute html =~ ~s(name="redirect_to")
      refute html =~ "evil.com"
    end
  end

  describe "OAuth sign-in" do
    test "returns to the booking form after the provider round trip", %{conn: conn} do
      insert(:user, provider: "github", github_user_id: "201")
      stub_github(%{"id" => 201}, [])

      conn = oauth_sign_in(conn, %{"return_to" => @return_to})

      assert redirected_to(conn) == @return_to
      refute get_session(conn, :oauth_return_to)
    end

    test "ignores a return_to that leaves the site", %{conn: conn} do
      insert(:user, provider: "github", github_user_id: "202")
      stub_github(%{"id" => 202}, [])

      conn = oauth_sign_in(conn, %{"return_to" => "https://evil.com/steal"})

      assert redirected_to(conn) == "/dashboard"
    end

    test "a flow started without return_to forgets one left by an abandoned flow",
         %{conn: conn} do
      insert(:user, provider: "github", github_user_id: "203")
      stub_github(%{"id" => 203}, [])

      abandoned = get(conn, "/auth/github", %{"return_to" => @return_to})
      assert get_session(abandoned, :oauth_return_to) == @return_to

      conn = abandoned |> recycle() |> oauth_sign_in(%{})

      assert redirected_to(conn) == "/dashboard"
    end
  end
end
