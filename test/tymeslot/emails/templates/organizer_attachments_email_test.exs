defmodule Tymeslot.Emails.Templates.OrganizerAttachmentsEmailTest do
  @moduledoc """
  The booker's attachments in the organiser's emails: listed in both bodies,
  and attached as files while they fit into one message.
  """

  use Tymeslot.DataCase, async: false

  @moduletag :emails

  import Tymeslot.EmailTestHelpers

  alias Ecto.UUID
  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Emails.Templates.AppointmentConfirmation
  alias Tymeslot.Emails.Templates.BookingApprovalRequest
  alias Tymeslot.Meetings.MeetingSchema, as: Meeting

  defp stored(name, content) do
    source = Path.join(System.tmp_dir!(), "mail-attachment-#{System.unique_integer([:positive])}")
    File.write!(source, content)

    {:ok, attachment} =
      AttendeeAttachments.store(
        AttendeeAttachments.new_batch(1),
        source,
        name,
        AttendeeAttachments.allowed_types()
      )

    attachment
  end

  defp file_attachments(email),
    do: Enum.filter(email.attachments, &(&1.content_type == "application/pdf"))

  describe "organiser confirmation" do
    test "lists and attaches the files" do
      attachment = stored("Brief.pdf", "%PDF-1.4 brief")
      details = build_appointment_details(%{attendee_attachments: [attachment]})

      email = AppointmentConfirmation.render(:organizer, "organizer@example.com", details)

      assert email.html_body =~ "Brief.pdf"
      assert email.text_body =~ "Brief.pdf"
      assert email.text_body =~ "attached to this email"
      assert [%{filename: "Brief.pdf", data: "%PDF-1.4 brief"}] = file_attachments(email)
    end

    test "only lists files too large to attach, pointing to the dashboard" do
      attachment = Map.put(stored("Big.pdf", "%PDF-1.4"), "byte_size", 16_000_000)
      details = build_appointment_details(%{attendee_attachments: [attachment]})

      email = AppointmentConfirmation.render(:organizer, "organizer@example.com", details)

      assert email.text_body =~ "Big.pdf"
      assert email.text_body =~ "too large to attach"
      assert email.text_body =~ "/dashboard/meetings"
      assert file_attachments(email) == []
    end

    test "says nothing about attachments when there are none" do
      email =
        AppointmentConfirmation.render(
          :organizer,
          "organizer@example.com",
          build_appointment_details()
        )

      refute email.text_body =~ "ATTACHMENTS"
      assert file_attachments(email) == []
    end

    test "the booker's own confirmation never carries the files" do
      attachment = stored("Brief.pdf", "%PDF-1.4 brief")
      details = build_appointment_details(%{attendee_attachments: [attachment]})

      email = AppointmentConfirmation.render(:attendee, details.attendee_email, details)

      assert file_attachments(email) == []
    end
  end

  test "the approval request lists and attaches the files" do
    attachment = stored("Brief.pdf", "%PDF-1.4 brief")

    meeting = %Meeting{
      id: UUID.generate(),
      uid: "abc-123",
      title: "Strategy call",
      meeting_type: "Strategy call",
      start_time: ~U[2026-09-01 13:00:00Z],
      end_time: ~U[2026-09-01 13:30:00Z],
      duration: 30,
      location: "Video Call",
      organizer_name: "Sam Host",
      organizer_email: "sam@example.com",
      attendee_name: "Alex Guest",
      attendee_email: "alex@example.com",
      attendee_timezone: "Europe/Ljubljana",
      attendee_locale: "en",
      approval_deadline_at: ~U[2026-08-30 09:00:00Z],
      status: "awaiting_approval",
      attendee_attachments: [attachment]
    }

    urls = %{
      review_url: "https://example.com/r",
      approve_url: "https://example.com/r?intent=approve",
      decline_url: "https://example.com/r?intent=decline"
    }

    email = BookingApprovalRequest.render(:request, meeting, urls, "en")

    assert email.html_body =~ "Brief.pdf"
    assert email.text_body =~ "Brief.pdf"
    assert [%{filename: "Brief.pdf"}] = file_attachments(email)
  end
end
