defmodule TymeslotWeb.Components.PublicTopBarTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :components
  @moduletag :themes

  import Phoenix.LiveViewTest
  alias TymeslotWeb.Components.PublicTopBar
  alias TymeslotWeb.Live.Shared.DocsUrl

  defp render_bar(extra \\ %{}) do
    render_component(
      &PublicTopBar.public_top_bar/1,
      Map.merge(%{locale: "en", locales: [], dropdown_open: false}, extra)
    )
  end

  setup do
    previous = Application.get_env(:tymeslot, :registration_enabled)
    on_exit(fn -> Application.put_env(:tymeslot, :registration_enabled, previous) end)
    Application.put_env(:tymeslot, :registration_enabled, true)
    :ok
  end

  test "anonymous visitor sees login and signup links" do
    html = render_bar()

    assert html =~ ~s(href="/auth/login")
    assert html =~ ~s(href="/auth/signup")
    refute html =~ ~s(href="/dashboard")
  end

  test "signup link is hidden when registration is disabled" do
    Application.put_env(:tymeslot, :registration_enabled, false)
    html = render_bar()

    assert html =~ ~s(href="/auth/login")
    refute html =~ ~s(href="/auth/signup")
  end

  test "logged-in user sees a dashboard link instead" do
    html = render_bar(%{current_user: %{id: 1}})

    assert html =~ ~s(href="/dashboard")
    refute html =~ ~s(href="/auth/login")
    refute html =~ ~s(href="/auth/signup")
  end

  test "embedded pages show no account links" do
    html = render_bar(%{embedded: true})

    refute html =~ "/auth/"
    refute html =~ ~s(href="/dashboard")
  end

  describe "logo" do
    test "links to the organizer's booking page" do
      html = render_bar(%{username: "jane"})

      assert html =~ ~s(href="/jane")
      assert html =~ ~s(aria-label="Booking page")
    end

    test "is not a link without an organizer" do
      refute render_bar() =~ ~s(aria-label="Booking page")
    end

    test "is not a link on embedded pages" do
      html = render_bar(%{username: "jane", embedded: true})

      refute html =~ ~s(href="/jane")
      refute html =~ ~s(aria-label="Booking page")
    end
  end

  describe "docs and website links" do
    setup do
      previous = Application.fetch_env(:tymeslot, :web_host)

      on_exit(fn ->
        case previous do
          {:ok, value} -> Application.put_env(:tymeslot, :web_host, value)
          :error -> Application.delete_env(:tymeslot, :web_host)
        end
      end)
    end

    test "link to the docs always, and to the website once WEB_HOST is set" do
      Application.put_env(:tymeslot, :web_host, nil)
      html = render_bar()

      assert html =~ ~s(aria-label="Documentation")
      assert html =~ ~s(href="#{DocsUrl.home_url()}")
      refute html =~ ~s(aria-label="Website")

      Application.put_env(:tymeslot, :web_host, "https://example.com")
      html = render_bar()

      assert html =~ ~s(aria-label="Website")
      assert html =~ ~s(href="https://example.com")
    end

    test "are left out of embedded pages" do
      Application.put_env(:tymeslot, :web_host, "https://example.com")
      html = render_bar(%{embedded: true})

      refute html =~ ~s(aria-label="Documentation")
      refute html =~ ~s(aria-label="Website")
    end
  end
end
