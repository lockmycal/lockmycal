defmodule TymeslotWeb.AdminLiveSettingRowTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :infrastructure

  import Tymeslot.AdminPageHelpers
  import Tymeslot.AppSettingsEnvHelpers

  alias Tymeslot.AppSettings

  setup :restore_app_settings_env

  setup :admin_conn

  describe "how a settings row signals that a setting is inactive" do
    test "a switched-off boolean keeps its own toggle at full opacity", %{conn: conn} do
      # Regression: the row dimmed itself whenever a boolean was off, which
      # dimmed the Enabled/Disabled pair too - so the one control that turns
      # the setting back on read as unclickable. The description may mute; the
      # control may not.
      {:ok, _settings} = AppSettings.update(%{admin_alerts_enabled: false})

      {:ok, _lv, html} = live_admin_settings_tab(conn, :email)

      # The description dims, saying "this is not doing anything right now".
      assert row_header_muted?(html, :admin_alerts_enabled)
      # The row wrapper must not, or the toggle inside it dims with it.
      refute row_wrapper_muted?(html, :admin_alerts_enabled)
    end

    test "a dependent control whose parent is off stays genuinely disabled", %{conn: conn} do
      # The other half of the same fix: admin_alert_email really is unusable
      # while alerts are off, so it must still render disabled.
      {:ok, _settings} = AppSettings.update(%{admin_alerts_enabled: false})

      {:ok, _lv, html} = live_admin_settings_tab(conn, :email)

      assert html =~ ~r/id="setting-input-admin_alert_email"[^>]*disabled/
    end
  end

  # The settings row for `key`: everything from the row wrapper's `id`
  # (`admin-setting-row-<key>`, added for exactly this kind of targeting) up
  # to the next row.
  defp settings_row(html, key) do
    chunk =
      html
      |> String.split(~s(<div id="admin-setting-row-))
      |> Enum.find(&String.starts_with?(&1, "#{key}\""))

    chunk || flunk("no settings row found for #{key}")
  end

  # True when the row wrapper itself is dimmed, which dims every descendant
  # including the control.
  defp row_wrapper_muted?(html, key) do
    case Regex.run(~r/^#{key}"\s+class="([^"]*)"/, settings_row(html, key)) do
      [_all, classes] -> String.contains?(classes, "opacity-60")
      nil -> flunk("no row wrapper class found for #{key}")
    end
  end

  # True when only the description block is dimmed.
  defp row_header_muted?(html, key) do
    chunk = settings_row(html, key)

    case Regex.run(~r/<div class="(flex-1 min-w-0[^"]*)"/, chunk) do
      [_all, classes] -> String.contains?(classes, "opacity-60")
      nil -> flunk("no row header found for #{key}")
    end
  end
end
