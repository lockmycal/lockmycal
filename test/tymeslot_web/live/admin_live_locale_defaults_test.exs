defmodule TymeslotWeb.AdminLiveLocaleDefaultsTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :i18n

  import Phoenix.LiveViewTest
  import Tymeslot.AdminPageHelpers
  import Tymeslot.AppSettingsEnvHelpers

  alias Tymeslot.AppSettings
  alias Tymeslot.Locales

  # Snapshots and restores every AppSettings key, the two locale defaults
  # included, so a language chosen here cannot leak into another test's
  # rendering.
  setup :restore_app_settings_env

  setup :admin_conn

  # The selected option in `key`'s <select> — the hidden `key` field precedes
  # the actual <select> in the DOM (see `LocaleSetting.locale_control/1`), so
  # anchor on that first, then find the marked `selected` option after it.
  # Returns the locale code ("" for the instance-default option), or :none
  # if no option in that block is marked selected at all.
  defp active_locale_select(html, key) do
    {start, _len} = :binary.match(html, ~s(name="key" value="#{key}"))
    rest = binary_part(html, start, byte_size(html) - start)

    case Regex.run(~r/<option selected[^>]*value="([a-z]*)"/, rest) do
      [_all, code] -> code
      nil -> :none
    end
  end

  describe "the Localisation section" do
    test "renders a Localisation section with one option per language per surface",
         %{conn: conn} do
      {:ok, _lv, html} = live_admin_settings_tab(conn, :general)

      assert html =~ "Localisation"
      assert html =~ "Dashboard fallback language"
      assert html =~ "Booking page fallback language"

      # Every configured language is offered on both surfaces, plus the
      # instance-default option: 2 surfaces x (6 languages + 1 default).
      options = Regex.scan(~r/<option[^>]*value="[a-z]*"/, html)
      assert length(options) == 2 * (length(Locales.supported_codes()) + 1)

      # Named by their endonyms, and the no-override option names the language
      # it actually resolves to rather than an abstract "instance default".
      assert html =~ "Deutsch"
      assert html =~ "Install default (English)"
    end

    test "the unset surface highlights the instance-default option, not a language",
         %{conn: conn} do
      {:ok, _lv, html} = live_admin_settings_tab(conn, :general)

      assert active_locale_select(html, "admin_default_locale") == ""
      assert active_locale_select(html, "booking_default_locale") == ""
    end

    test "choosing a language moves the highlight onto it", %{conn: conn} do
      {:ok, lv, _html} = live_admin_settings_tab(conn, :general)

      html =
        lv
        |> with_target("#admin-hub")
        |> render_click("set_locale", %{"key" => "booking_default_locale", "locale" => "de"})

      assert active_locale_select(html, "booking_default_locale") == "de"
      # The other surface is untouched, so its default stays highlighted.
      assert active_locale_select(html, "admin_default_locale") == ""
    end

    test "choosing a booking fallback language persists it and takes effect immediately",
         %{conn: conn} do
      {:ok, lv, _html} = live_admin_settings_tab(conn, :general)

      lv
      |> with_target("#admin-hub")
      |> render_click("set_locale", %{
        "key" => "booking_default_locale",
        "locale" => "de"
      })

      assert flash_html(lv) =~ "Booking page fallback language updated."
      assert %{booking_default_locale: "de"} = AppSettings.get!()
      assert Locales.booking_default_locale() == "de"

      # The two surfaces are independent: setting one must not move the other.
      assert Locales.admin_default_locale() == Locales.default_locale()
    end

    test "choosing an admin fallback language persists it independently", %{conn: conn} do
      {:ok, lv, _html} = live_admin_settings_tab(conn, :general)

      lv
      |> with_target("#admin-hub")
      |> render_click("set_locale", %{"key" => "admin_default_locale", "locale" => "fr"})

      assert flash_html(lv) =~ "Dashboard fallback language updated."
      assert Locales.admin_default_locale() == "fr"
      assert Locales.booking_default_locale() == Locales.default_locale()
    end

    test "clearing the select removes the override", %{conn: conn} do
      {:ok, _settings} = AppSettings.update(%{admin_default_locale: "de"})

      {:ok, lv, _html} = live_admin_settings_tab(conn, :general)

      lv
      |> with_target("#admin-hub")
      |> render_click("set_locale", %{"key" => "admin_default_locale", "locale" => ""})

      assert %{admin_default_locale: nil} = AppSettings.get!()
      assert Locales.admin_default_locale() == Locales.default_locale()
    end

    test "a locale code outside the supported set is refused with an inline error",
         %{conn: conn} do
      {:ok, lv, _html} = live_admin_settings_tab(conn, :general)

      lv
      |> with_target("#admin-hub")
      |> render_click("set_locale", %{"key" => "booking_default_locale", "locale" => "zz"})

      assert flash_html(lv) =~ "Choose one of the supported languages."
      assert %{booking_default_locale: nil} = AppSettings.get!()
    end
  end

  # `HubComponent` forwards flash messages to the parent `DashboardLive` via
  # `Flash.put_flash/3` (a `send(self(), {:flash, ...})`, since
  # `Phoenix.LiveView.put_flash/3` on a component's own socket is silently
  # dropped), so it lands one `handle_info/2` round-trip after the
  # `render_click` that triggered it — `drain/1` forces that message to be
  # processed before re-rendering (same pattern used elsewhere for the same
  # reason).
  defp drain(lv), do: :sys.get_state(lv.pid)

  defp flash_html(lv) do
    drain(lv)
    render(lv)
  end
end
