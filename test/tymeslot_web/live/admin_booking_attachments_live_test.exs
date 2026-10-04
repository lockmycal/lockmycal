defmodule TymeslotWeb.AdminBookingAttachmentsLiveTest do
  @moduledoc """
  The admin's booking-attachment limits on the General settings tab.
  """

  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :bookings

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.AppSettingsEnvHelpers, only: [restore_app_settings_env: 1]
  import Tymeslot.Factory

  alias Tymeslot.AppSettings
  alias Tymeslot.Infrastructure.DashboardCache

  setup_all do
    case Process.whereis(DashboardCache) do
      nil -> start_supervised!(DashboardCache)
      _pid -> :ok
    end

    :ok
  end

  setup :restore_app_settings_env

  setup do
    original_router = Application.get_env(:tymeslot, :router)
    original_uploads = Application.get_env(:tymeslot, :uploads)
    Application.put_env(:tymeslot, :router, TymeslotWeb.Router)
    Application.put_env(:tymeslot, :enable_admin_ui, true)
    DashboardCache.clear_all()

    on_exit(fn ->
      if original_router,
        do: Application.put_env(:tymeslot, :router, original_router),
        else: Application.delete_env(:tymeslot, :router)

      if original_uploads,
        do: Application.put_env(:tymeslot, :uploads, original_uploads),
        else: Application.delete_env(:tymeslot, :uploads)
    end)

    admin = insert(:user, is_admin: true, onboarding_completed_at: DateTime.utc_now(:second))
    insert(:profile, user: admin, username: "admin-#{admin.id}")
    %{admin: admin}
  end

  test "toggles a file type off and on again", %{conn: conn, admin: admin} do
    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin")

    assert has_element?(lv, "#admin-setting-row-booking_attachment_types")
    assert has_element?(lv, "#admin-attachment-type-zip[aria-pressed='true']")

    lv |> element("#admin-attachment-type-zip") |> render_click()

    assert AppSettings.get(:booking_attachment_types) ==
             ~w(csv docx jpeg jpg md ods odt pdf png pptx txt webp xlsx)

    assert has_element?(lv, "#admin-attachment-type-zip[aria-pressed='false']")

    lv |> element("#admin-attachment-type-zip") |> render_click()

    assert AppSettings.get(:booking_attachment_types) ==
             ~w(csv docx jpeg jpg md ods odt pdf png pptx txt webp xlsx zip)
  end

  test "SVG is off by default and can be switched on", %{conn: conn, admin: admin} do
    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin")

    assert has_element?(lv, "#admin-attachment-type-svg[aria-pressed='false']")

    lv |> element("#admin-attachment-type-svg") |> render_click()
    assert "svg" in AppSettings.get(:booking_attachment_types)
  end

  test "saves the size and count limits and rejects out-of-range values", %{
    conn: conn,
    admin: admin
  } do
    {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/dashboard/admin")

    lv
    |> form("#admin-setting-form-max_booking_attachment_size_mb", %{"value" => "25"})
    |> render_submit()

    assert AppSettings.get(:max_booking_attachment_size_mb) == 25

    lv
    |> form("#admin-setting-form-max_booking_attachments", %{"value" => "11"})
    |> render_submit()

    assert render(lv) =~ "Enter a whole number of files (1-10)."
    assert AppSettings.get(:max_booking_attachments) == 3
  end
end
