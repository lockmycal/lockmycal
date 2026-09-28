defmodule TymeslotWeb.DashboardAppearanceTopbarTest do
  @moduledoc """
  Covers the topbar sun/moon appearance quick toggle
  (`DashboardLayout.top_navigation/1`, `AppearanceToggle` JS hook,
  `DashboardLive`'s `"change_appearance"` handler). Unlike Profile Settings'
  3-way `<.option_toggle>`, this button carries no `phx-click`/`phx-value-*`
  — the hook computes the target value client-side and pushes it itself, so
  the round-trip is exercised here via `render_hook/3` (what the hook's
  `pushEvent` call does) rather than `render_click/1`.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :dashboard
  @moduletag :live

  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Repo

  setup :setup_dashboard_user

  describe "the topbar appearance toggle" do
    test "is present, hooked, and needs no phx-click of its own", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

      doc = Floki.parse_document!(html)
      buttons = Floki.find(doc, "button#appearance-topbar-toggle")

      assert buttons != []
      assert Floki.attribute(buttons, "phx-hook") == ["AppearanceToggle"]
      assert Floki.attribute(buttons, "data-appearance-flip") == [""]
    end

    test "persists the value the hook pushes, from any dashboard page", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      render_hook(view, "change_appearance", %{"value" => "dark"})

      assert Repo.get(UserSchema, user.id).theme_preference == "dark"
    end

    test "a fresh page load then renders <html class=\"dark\">", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      render_hook(view, "change_appearance", %{"value" => "dark"})

      {:ok, _reloaded, html} = live(conn, ~p"/dashboard/overview")

      assert html =~ ~s(class="dark")
    end

    test "flipping back to light clears the dark class on the next load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      render_hook(view, "change_appearance", %{"value" => "dark"})
      render_hook(view, "change_appearance", %{"value" => "light"})

      {:ok, _reloaded, html} = live(conn, ~p"/dashboard/overview")

      refute html =~ ~s(class="dark")
    end
  end
end
