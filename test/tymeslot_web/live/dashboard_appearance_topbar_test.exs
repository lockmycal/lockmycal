defmodule TymeslotWeb.DashboardAppearanceTopbarTest do
  @moduledoc """
  Covers the top bar's Light / System / Dark switch
  (`DashboardLayout.top_navigation/1`, `AppearanceToggle` JS hook) and the
  saving of its `change_appearance` event by `AppAppearanceHook`, which every
  dashboard LiveView rendering the layout runs.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :dashboard
  @moduletag :live

  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Repo

  setup :setup_dashboard_user

  defp switch_button(view, option),
    do: element(view, "#appearance-topbar-switch button[phx-value-option='#{option}']")

  describe "the top bar appearance switch" do
    test "offers light, system and dark, marking the saved choice", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

      doc = Floki.parse_document!(html)
      assert Floki.attribute(doc, "#appearance-topbar-switch", "phx-hook") == ["AppearanceToggle"]

      assert doc
             |> Floki.find("#appearance-topbar-switch button")
             |> Enum.flat_map(&Floki.attribute(&1, "phx-value-option")) ==
               ["light", "system", "dark"]

      # No preference saved yet: "system" is the active one.
      assert Floki.attribute(
               doc,
               "#appearance-topbar-switch button[phx-value-option='system']",
               "aria-pressed"
             ) == ["true"]
    end

    test "saves the choice and marks it", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      view |> switch_button("dark") |> render_click()

      assert Repo.get(UserSchema, user.id).theme_preference == "dark"
      assert view |> switch_button("dark") |> render() =~ ~s(aria-pressed="true")
    end

    test "a fresh page load then renders <html class=\"dark\">", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      view |> switch_button("dark") |> render_click()

      {:ok, _reloaded, html} = live(conn, ~p"/dashboard/overview")

      assert html =~ ~s(class="dark")
    end

    test "system clears the saved preference", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      view |> switch_button("dark") |> render_click()
      view |> switch_button("system") |> render_click()

      assert Repo.get(UserSchema, user.id).theme_preference == nil

      {:ok, _reloaded, html} = live(conn, ~p"/dashboard/overview")
      refute html =~ ~s(class="dark")
    end

    test "works on the analytics page too", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/analytics")

      view |> switch_button("light") |> render_click()

      assert Repo.get(UserSchema, user.id).theme_preference == "light"
    end
  end
end
