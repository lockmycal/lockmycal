defmodule TymeslotWeb.MeetingAttachmentController do
  @moduledoc """
  Lets a meeting's organiser download a file the booker attached
  (`Tymeslot.Bookings.AttendeeAttachments`).

  Behind the authenticated dashboard pipeline, and scoped to the signed-in
  user as the meeting's organiser: every other case is a plain 404. The file
  is always sent as a download, never rendered inline, with `nosniff` so a
  browser cannot reinterpret an uploaded document as something executable.
  """

  use TymeslotWeb, :controller

  alias Tymeslot.Bookings.AttendeeAttachments

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"meeting_id" => meeting_id, "attachment_id" => attachment_id}) do
    user = conn.assigns.current_user

    case AttendeeAttachments.fetch_for_organizer(meeting_id, attachment_id, user.id) do
      {:ok, attachment, path} ->
        conn
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("cache-control", "private, no-store")
        |> send_download({:file, path},
          filename: attachment["filename"],
          content_type: attachment["content_type"]
        )

      {:error, :not_found} ->
        conn |> put_resp_content_type("text/plain") |> send_resp(404, "")
    end
  end
end
