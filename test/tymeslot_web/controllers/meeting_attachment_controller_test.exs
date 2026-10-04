defmodule TymeslotWeb.MeetingAttachmentControllerTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :bookings
  @moduletag :controllers

  import Tymeslot.AuthTestHelpers, only: [log_in_user: 2]
  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Bookings.AttendeeAttachments

  setup :setup_dashboard_user

  setup %{user: user} do
    source = Path.join(System.tmp_dir!(), "attachment-#{System.unique_integer([:positive])}")
    File.write!(source, "%PDF-1.4 contract")

    {:ok, attachment} =
      AttendeeAttachments.store(
        AttendeeAttachments.new_batch(user.id),
        source,
        "Smlouva č. 1.pdf",
        AttendeeAttachments.allowed_types()
      )

    meeting = insert(:meeting, organizer_user_id: user.id, attendee_attachments: [attachment])
    %{attachment: attachment, meeting: meeting}
  end

  defp download_path(meeting, attachment),
    do: ~p"/dashboard/meetings/#{meeting.id}/attachments/#{attachment["id"]}"

  test "the organiser downloads the file as an attachment", %{
    conn: conn,
    meeting: meeting,
    attachment: attachment
  } do
    conn = get(conn, download_path(meeting, attachment))

    assert conn.status == 200
    assert conn.resp_body == "%PDF-1.4 contract"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"
    assert disposition =~ "filename*=utf-8''Smlouva"
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "application/pdf"
  end

  @tag :cross_tenant
  test "another user gets a 404", %{meeting: meeting, attachment: attachment} do
    other = insert(:user, onboarding_completed_at: DateTime.utc_now())
    insert(:profile, user: other)

    conn =
      build_conn()
      |> init_test_session(%{})
      |> log_in_user(other)
      |> get(download_path(meeting, attachment))

    assert conn.status == 404
  end

  test "an unknown attachment is a 404", %{conn: conn, meeting: meeting} do
    conn = get(conn, ~p"/dashboard/meetings/#{meeting.id}/attachments/nope")
    assert conn.status == 404
  end

  test "a signed-out visitor is sent to log in", %{meeting: meeting, attachment: attachment} do
    conn = get(build_conn(), download_path(meeting, attachment))
    assert redirected_to(conn) =~ "/auth/login"
  end

  test "the file is never reachable under the public /uploads mount", %{attachment: attachment} do
    conn = get(build_conn(), "/uploads/" <> attachment["stored_path"])
    assert conn.status == 404
  end
end
