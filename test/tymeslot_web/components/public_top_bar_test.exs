defmodule TymeslotWeb.Components.PublicTopBarTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :components
  @moduletag :themes

  import Phoenix.LiveViewTest
  alias TymeslotWeb.Components.PublicTopBar

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
end
