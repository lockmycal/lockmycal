defmodule TymeslotWeb.Dashboard.ProfileSettingsLanguageTest do
  @moduledoc """
  Dashboard language preference, moved from the old standalone
  `/dashboard/account` page's button-per-locale switcher into
  `LanguageFormComponent`'s `<select>` on the Profile page. See
  `ProfileSettingsEmailTest` for why this is a separate file.
  """

  use TymeslotWeb.LiveCase, async: false
  @moduletag :profiles
  @moduletag :live

  import Tymeslot.DashboardTestHelpers

  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Repo

  setup :setup_dashboard_user

  describe "rendering" do
    test "shows a language selector with Automatic selected by default", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/settings")

      assert html =~ "Language"
      assert html =~ "Automatic"
      assert html =~ "Deutsch"
    end
  end

  describe "changing the language" do
    test "persists it and re-renders the whole page in the new locale", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      {:ok, _view, html} =
        view
        |> element("#language-form")
        |> render_change(%{"locale" => "de"})
        |> follow_redirect(conn)

      # Persisted immediately, no separate save step.
      assert Repo.get(UserSchema, user.id).locale == "de"

      # Confirmation flash renders in German. Re-supplies the translation that
      # commit 028a0383d ("refactor(core): switch account language selector
      # to flag buttons") silently dropped during a gettext domain/context
      # change (see priv/gettext/de/LC_MESSAGES/dashboard_profile.po).
      assert html =~ "Spracheinstellung gespeichert."

      # The remount re-renders every string in German - including ones that
      # depend on no assign and would otherwise stay frozen by LiveView change
      # tracking.
      assert html =~ "Sprache"
    end

    test "switching to Automatic clears the persisted locale", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      {:ok, view, _html} =
        view
        |> element("#language-form")
        |> render_change(%{"locale" => "de"})
        |> follow_redirect(conn)

      assert Repo.get(UserSchema, user.id).locale == "de"

      {:ok, _view, _html} =
        view
        |> element("#language-form")
        |> render_change(%{"locale" => ""})
        |> follow_redirect(conn)

      assert Repo.get(UserSchema, user.id).locale == nil
    end
  end
end
