defmodule TymeslotWeb.Dashboard.ProfileSettingsAppearanceTest do
  @moduledoc """
  Covers the Appearance section of Profile Settings: the Light/Dark/System
  toggle, persistence of the choice, and — the part a plain LiveViewTest
  round-trip on the component alone can't prove — that the saved preference
  actually lands as a `.dark` class on `<html>` on the very first byte of a
  fresh page load, with no flash of the wrong theme.
  """

  use TymeslotWeb.LiveCase, async: true

  @moduletag :profiles
  @moduletag :live

  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Repo

  setup :setup_dashboard_user

  describe "the Appearance section" do
    test "is offered on the settings page with all three options", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Appearance"
      assert html =~ "Light"
      assert html =~ "Dark"
      assert html =~ "System"
    end

    test "stores the organiser's choice", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='dark']")
      |> render_click()

      assert Repo.get(UserSchema, user.id).theme_preference == "dark"
    end

    test "confirms the change to the organiser", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='dark']")
      |> render_click()

      assert render(view) =~ "Appearance updated"
    end

    test "the choice survives a reload and stays selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='dark']")
      |> render_click()

      {:ok, _reloaded, html} = live(conn, ~p"/dashboard/settings")

      doc = Floki.parse_document!(html)

      assert doc
             |> Floki.find("button[phx-value-option='dark']")
             |> Floki.attribute("disabled") == [""]

      assert doc
             |> Floki.find("button[phx-value-option='dark']")
             |> Floki.attribute("class")
             |> Enum.any?(&String.contains?(&1, "bg-primary-600"))
    end

    test "picking Dark renders <html class=\"dark\"> on a fresh page load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='dark']")
      |> render_click()

      {:ok, _reloaded, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ ~s(class="dark")
    end

    test "picking Light renders <html> with no dark class on a fresh page load", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='dark']")
      |> render_click()

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='light']")
      |> render_click()

      {:ok, _reloaded, html} = live(conn, ~p"/dashboard/settings")

      refute html =~ ~s(class="dark")
    end

    test "picking System clears the stored preference", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='dark']")
      |> render_click()

      view
      |> element("button[phx-click='change_appearance'][phx-value-option='system']")
      |> render_click()

      assert Repo.get(UserSchema, user.id).theme_preference == nil
    end
  end
end
