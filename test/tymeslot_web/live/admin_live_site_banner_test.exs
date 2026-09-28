defmodule TymeslotWeb.AdminLiveSiteBannerTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :ui

  import Phoenix.LiveViewTest
  import Tymeslot.AppSettingsEnvHelpers
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.AppSettings

  setup :restore_app_settings_env

  setup %{conn: conn} do
    original_router = Application.get_env(:tymeslot, :router)
    Application.put_env(:tymeslot, :router, TymeslotWeb.Router)
    Application.put_env(:tymeslot, :enable_admin_ui, true)

    on_exit(fn ->
      if original_router,
        do: Application.put_env(:tymeslot, :router, original_router),
        else: Application.delete_env(:tymeslot, :router)

      Application.put_env(:tymeslot, :enable_admin_ui, true)
    end)

    admin = insert(:user, is_admin: true, onboarding_completed_at: DateTime.utc_now(:second))
    {:ok, conn: log_in_user(conn, admin)}
  end

  test "the section renders on the General tab with its controls and an empty preview",
       %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/dashboard/admin")

    assert html =~ "admin-site-banner-section"
    assert html =~ "setting-input-site_banner_message"
    assert html =~ "setting-input-site_banner_colour"
    assert html =~ "admin-setting-row-site_banner_public_enabled"
    assert html =~ "Set a banner message to see a preview."
  end

  test "saving the message stores it sanitised and updates the preview", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

    html =
      lv
      |> form("#admin-setting-form-site_banner_message", %{
        "key" => "site_banner_message",
        "value" => ~s|<b class="x">Maintenance</b><script>x()</script>|
      })
      |> render_submit()

    assert AppSettings.get!().site_banner_message == ~s|<b class="x">Maintenance</b>x()|
    assert html =~ "admin-site-banner-preview"
  end

  test "saving the colour normalises it", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

    lv
    |> form("#admin-setting-hex-form-site_banner_colour", %{
      "key" => "site_banner_colour",
      "value" => "#AABBCC"
    })
    |> render_submit()

    assert AppSettings.get!().site_banner_colour == "#aabbcc"
  end

  test "each surface switch toggles independently", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

    lv
    |> element(~s|#admin-setting-row-site_banner_public_enabled button[phx-value-state="true"]|)
    |> render_click()

    assert %{site_banner_public_enabled: true, site_banner_app_enabled: nil} = AppSettings.get!()
  end

  describe "message translations" do
    setup do
      {:ok, _settings} = AppSettings.update(%{site_banner_message: "Base message"})
      :ok
    end

    defp switch_locale(lv, locale) do
      lv
      |> with_target("#admin-hub")
      |> render_click("switch_site_banner_locale", %{"option" => locale})
    end

    test "a non-default language tab edits that locale's row, not the base message",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      html = switch_locale(lv, "cs")
      assert html =~ "admin-site-banner-translation-form-cs"
      refute html =~ ~s|id="admin-setting-form-site_banner_message"|
      # A blank translation previews (and falls back to) the base message.
      assert html =~ "Base message"

      html =
        lv
        |> form("#admin-site-banner-translation-form-cs", %{
          "locale" => "cs",
          "value" => "Česká zpráva"
        })
        |> render_submit()

      assert %{site_banner_message: "Base message", site_banner_translations: [row]} =
               AppSettings.get!()

      assert %{locale: "cs", message: "Česká zpráva"} = row
      assert html =~ "Česká zpráva"
    end

    test "saving another language keeps the existing rows", %{conn: conn} do
      {:ok, _settings} =
        AppSettings.update(%{site_banner_translations: [%{"locale" => "cs", "message" => "CZ"}]})

      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")
      switch_locale(lv, "de")

      lv
      |> form("#admin-site-banner-translation-form-de", %{"locale" => "de", "value" => "DE"})
      |> render_submit()

      assert [%{locale: "cs", message: "CZ"}, %{locale: "de", message: "DE"}] =
               AppSettings.get!().site_banner_translations
    end

    test "an unsupported locale is ignored", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard/admin")

      lv
      |> with_target("#admin-hub")
      |> render_click("save_site_banner_translation", %{"locale" => "zz", "value" => "x"})

      assert AppSettings.get!().site_banner_translations == []
    end
  end
end
