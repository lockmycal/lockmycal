defmodule TymeslotWeb.Components.Dashboard.Meetings.AttendeeAttachmentsTest do
  use TymeslotWeb.ConnCase, async: true

  @moduletag :dashboard
  @moduletag :components

  import Phoenix.LiveViewTest
  import Tymeslot.Factory

  alias Ecto.UUID
  alias TymeslotWeb.Components.Dashboard.Meetings.AttendeeAttachments
  alias TymeslotWeb.Components.Dashboard.Meetings.MeetingCardComponents

  @attachment %{
    "id" => "a1",
    "filename" => "Brief.pdf",
    "content_type" => "application/pdf",
    "byte_size" => 2_500_000
  }

  describe "booking card" do
    defp card(meeting, current_user_email) do
      render_component(&MeetingCardComponents.meeting_card/1,
        meeting: meeting,
        profile: nil,
        time_format: "24h",
        current_user_email: current_user_email,
        cancelling_meeting: nil,
        sending_reschedule: nil,
        deleting_meeting: nil,
        target: nil
      )
    end

    test "shows the paperclip badge and download links to the organiser" do
      meeting =
        build(:meeting,
          id: UUID.generate(),
          organizer_email: "host@example.com",
          attendee_attachments: [@attachment]
        )

      html = card(meeting, "host@example.com")

      assert html =~ ~s(data-testid="attachments-badge")
      assert html =~ "/dashboard/meetings/#{meeting.id}/attachments/a1"
      assert html =~ "2.5 MB"
    end

    test "shows the badge but no links to a mere attendee" do
      meeting =
        build(:meeting,
          id: UUID.generate(),
          organizer_email: "host@example.com",
          attendee_attachments: [@attachment]
        )

      html = card(meeting, "someone@example.com")

      assert html =~ ~s(data-testid="attachments-badge")
      refute html =~ "/attachments/a1"
    end

    test "has no paperclip without attachments" do
      html = card(build(:meeting, id: UUID.generate()), "host@example.com")
      refute html =~ "attachments-badge"
    end
  end

  describe "calendar marker" do
    test "renders only for an event with attachments" do
      assert render_component(&AttendeeAttachments.marker/1, attachments: [@attachment]) =~
               "attachments-marker"

      refute render_component(&AttendeeAttachments.marker/1, attachments: []) =~
               "attachments-marker"

      refute render_component(&AttendeeAttachments.marker/1, attachments: nil) =~
               "attachments-marker"
    end
  end
end
