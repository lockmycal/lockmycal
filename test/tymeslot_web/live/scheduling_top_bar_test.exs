defmodule TymeslotWeb.Live.SchedulingTopBarTest do
  @moduledoc """
  The public booking page's top bar shows Login / Get Started to an anonymous
  visitor and a Dashboard link to a signed-in one, on both booking themes,
  and its logo links back to the organizer's booking page. The footer below
  links to the website's bug forum.
  """
  use TymeslotWeb.ConnCase, async: false
  @moduletag :themes
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.Factory
  import Mox
  import Tymeslot.AuthTestHelpers, only: [log_in_user: 2]

  setup do
    user = insert(:user)
    profile = insert(:profile, user: user, username: "topbaruser")

    stub(Tymeslot.CalendarMock, :get_events_for_range_fresh, fn _integration, _start, _end ->
      {:ok, []}
    end)

    insert(:calendar_integration, user: user, provider: "google", is_active: true)

    insert(:meeting_type,
      user: user,
      name: "Test Meeting",
      slug: "test-meeting",
      duration_minutes: 30,
      is_active: true
    )

    {:ok, user: user, username: profile.username}
  end

  for theme <- ["1", "2"], page <- ["cancel", "reschedule"] do
    describe "theme #{theme}, #{page} page" do
      test "shows login for anonymous and dashboard for signed-in", %{
        conn: conn,
        user: user,
        username: username
      } do
        meeting = insert(:meeting, organizer_user: user)
        path = "/#{username}/meeting/#{meeting.uid}/#{unquote(page)}?theme=#{unquote(theme)}"

        {:ok, _view, html} = live(conn, path)
        assert html =~ ~s(href="/auth/login")
        refute html =~ ~s(href="/dashboard")

        {:ok, _view, html} = live(log_in_user(conn, user), path)
        assert html =~ ~s(href="/dashboard")
        refute html =~ ~s(href="/auth/login")
      end

      test "logo links to the booking page", %{conn: conn, user: user, username: username} do
        meeting = insert(:meeting, organizer_user: user)
        path = "/#{username}/meeting/#{meeting.uid}/#{unquote(page)}?theme=#{unquote(theme)}"

        {:ok, _view, html} = live(conn, path)
        assert logo_href(html) == "/#{username}"
      end
    end
  end

  for theme <- ["1", "2"] do
    describe "theme #{theme}" do
      test "anonymous visitor sees login and signup links", %{conn: conn, username: username} do
        {:ok, _view, html} = live(conn, "/#{username}?theme=#{unquote(theme)}")

        assert html =~ ~s(href="/auth/login")
        assert html =~ ~s(href="/auth/signup")
        refute html =~ ~s(href="/dashboard")
      end

      test "signed-in user sees a dashboard link", %{conn: conn, user: user, username: username} do
        conn = log_in_user(conn, user)
        {:ok, _view, html} = live(conn, "/#{username}?theme=#{unquote(theme)}")

        assert html =~ ~s(href="/dashboard")
        refute html =~ ~s(href="/auth/login")
      end

      test "footer links to the bug forum once WEB_HOST is set", %{
        conn: conn,
        username: username
      } do
        previous = Application.fetch_env(:tymeslot, :web_host)

        on_exit(fn ->
          case previous do
            {:ok, value} -> Application.put_env(:tymeslot, :web_host, value)
            :error -> Application.delete_env(:tymeslot, :web_host)
          end
        end)

        Application.put_env(:tymeslot, :web_host, "https://example.com")
        {:ok, _view, html} = live(conn, "/#{username}?theme=#{unquote(theme)}")

        assert html
               |> Floki.parse_document!()
               |> Floki.attribute("footer.public-footer a", "href") ==
                 ["https://example.com/forum/bugs"]
      end

      test "logo links to the booking page from a later step", %{
        conn: conn,
        username: username
      } do
        {:ok, _view, html} = live(conn, "/#{username}/test-meeting?theme=#{unquote(theme)}")

        assert logo_href(html) == "/#{username}"
      end
    end
  end

  defp logo_href(html) do
    html
    |> Floki.parse_document!()
    |> Floki.attribute(".public-top-bar-brand a", "href")
    |> List.first()
  end
end
