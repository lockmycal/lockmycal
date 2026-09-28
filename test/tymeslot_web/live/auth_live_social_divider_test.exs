defmodule TymeslotWeb.AuthLiveSocialDividerTest do
  use TymeslotWeb.LiveCase, async: false

  @moduletag :auth
  @moduletag :live

  setup do
    original = Application.get_env(:tymeslot, :social_auth)
    on_exit(fn -> Application.put_env(:tymeslot, :social_auth, original) end)
    :ok
  end

  defp put_social_auth(opts) do
    Application.put_env(
      :tymeslot,
      :social_auth,
      Keyword.merge([google_enabled: false, github_enabled: false, oauth_enabled: false], opts)
    )
  end

  for path <- ["/auth/login", "/auth/signup"] do
    describe path do
      test "hides the \"Or continue with\" divider when no provider is enabled", %{conn: conn} do
        put_social_auth([])

        {:ok, _view, html} = live(conn, unquote(path))

        refute html =~ "Or continue with"
        refute html =~ "btn-oauth"
      end

      test "shows the divider together with the enabled provider's button", %{conn: conn} do
        put_social_auth(github_enabled: true)

        {:ok, _view, html} = live(conn, unquote(path))

        assert html =~ "Or continue with"
        assert html =~ ~s(href="/auth/github")
      end
    end
  end
end
