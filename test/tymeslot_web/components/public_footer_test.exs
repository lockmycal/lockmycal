defmodule TymeslotWeb.Components.PublicFooterTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :components
  @moduletag :themes

  import Phoenix.LiveViewTest
  alias TymeslotWeb.Components.PublicFooter

  setup do
    previous = Application.fetch_env(:tymeslot, :web_host)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:tymeslot, :web_host, value)
        :error -> Application.delete_env(:tymeslot, :web_host)
      end
    end)
  end

  defp render_footer(assigns \\ %{}) do
    render_component(&PublicFooter.public_footer/1, assigns)
  end

  test "links to the website's bug forum in a new tab once WEB_HOST is set" do
    Application.put_env(:tymeslot, :web_host, "https://example.com")
    html = render_footer()

    assert html =~ ~s(href="https://example.com/forum/bugs")
    assert html =~ ~s(target="_blank")
    assert html =~ "Report a bug"
  end

  test "shows the app name and version, without the bug link while WEB_HOST is unset" do
    Application.put_env(:tymeslot, :web_host, nil)
    html = render_footer()

    assert html =~ "Powered by LockMyCal · v#{Application.spec(:tymeslot, :vsn)}"
    refute html =~ "Report a bug"
  end

  test "renders nothing on embedded pages" do
    Application.put_env(:tymeslot, :web_host, "https://example.com")

    refute render_footer(%{embedded: true}) =~ "<footer"
  end
end
