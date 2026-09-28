defmodule TymeslotWeb.Helpers.PageTitlesTest do
  use ExUnit.Case, async: true

  @moduletag :utils

  alias TymeslotWeb.Helpers.PageTitles

  test ":calendar returns the bare dashboard title as the landing mode" do
    assert PageTitles.dashboard_title(:calendar) == "Dashboard"
  end

  test ":overview returns the overview section title" do
    assert PageTitles.dashboard_title(:overview) == "Overview - Dashboard"
  end

  test ":calendar_integration returns the integration settings title" do
    assert PageTitles.dashboard_title(:calendar_integration) == "Calendars - Dashboard"
  end

  test ":video_integration returns the video integration title" do
    assert PageTitles.dashboard_title(:video_integration) == "Video - Dashboard"
  end

  test ":admin returns the admin hub title" do
    assert PageTitles.dashboard_title(:admin) == "Admin - Dashboard"
  end

  test ":admin_users returns the admin users tab title" do
    assert PageTitles.dashboard_title(:admin_users) == "Admin Users - Dashboard"
  end
end
