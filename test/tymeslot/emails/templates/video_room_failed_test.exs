defmodule Tymeslot.Emails.Templates.VideoRoomFailedTest do
  use Tymeslot.DataCase, async: true
  @moduletag :emails

  alias Tymeslot.Auth.UserQueries
  alias Tymeslot.Emails.RecipientLocale
  alias Tymeslot.Emails.Shared.Formatting
  alias Tymeslot.Emails.Templates.VideoRoomFailed
  alias Tymeslot.Profiles

  import Tymeslot.Factory
  import Tymeslot.TestFixtures

  describe "VideoRoomFailed.render/1" do
    test "generates valid HTML output" do
      meeting = insert(:meeting)

      html = VideoRoomFailed.render(meeting)

      assert html =~ "</html>"
      assert html =~ "Video Setup Failed"
      assert html =~ "Meeting Details"
    end

    test "includes meeting details" do
      meeting = insert(:meeting, location: "Conference Room A", duration: 60)

      html = VideoRoomFailed.render(meeting)

      assert html =~ "Conference Room A"
    end

    test "handles missing organizer_user_id with fallback timezone" do
      meeting = insert(:meeting, organizer_user_id: nil)

      html = VideoRoomFailed.render(meeting)

      fallback_local = DateTime.shift_zone!(meeting.start_time, Profiles.get_default_timezone())

      assert html =~ Formatting.format_time(fallback_local, "en")
      assert html =~ "Video Setup Failed"
    end

    test "converts meeting time to owner's timezone" do
      profile = insert(:profile, timezone: "America/New_York")
      meeting = insert(:meeting, organizer_user: profile.user)

      html = VideoRoomFailed.render(meeting)

      owner_local = DateTime.shift_zone!(meeting.start_time, "America/New_York")

      assert html =~ Formatting.format_time(owner_local, "en")
      refute html =~ Formatting.format_time(meeting.start_time, "en")
    end

    test "includes what-you-can-do section" do
      meeting = insert(:meeting)

      html = VideoRoomFailed.render(meeting)

      assert html =~ "What you can do"
    end
  end

  describe "VideoRoomFailed.render_both/1" do
    test "returns a {html, text} tuple equivalent to calling render/1 and render_text/1 separately" do
      meeting = insert(:meeting)

      {html, text} = VideoRoomFailed.render_both(meeting)

      assert html == VideoRoomFailed.render(meeting)
      assert text == VideoRoomFailed.render_text(meeting)
    end
  end

  describe "VideoRoomFailed.render_text/1" do
    test "returns plain text with meeting details" do
      meeting = insert(:meeting, location: "Conference Room A", duration: 60)

      text = VideoRoomFailed.render_text(meeting)

      assert text =~ "Video Setup Failed"
      assert text =~ "Conference Room A"
      assert text =~ "1 hour"
      assert text =~ "manually"
    end

    test "renders in the organizer's locale" do
      user = create_user_fixture()
      {:ok, user} = UserQueries.update_user_locale(user, "de")
      meeting = insert(:meeting, organizer_user_id: user.id, duration: 60)

      text =
        RecipientLocale.with_user_id_locale(user.id, fn ->
          VideoRoomFailed.render_text(meeting)
        end)

      assert text =~ "1 Stunde"
      refute text =~ "MEETING DETAILS:"
    end

    test "handles missing organizer_user_id" do
      meeting = insert(:meeting, organizer_user_id: nil, duration: 60)

      text = VideoRoomFailed.render_text(meeting)

      assert text =~ "Video Setup Failed"
      assert text =~ "Duration: 1 hour"
    end
  end

  describe "render_text security" do
    test "handles malicious location without crashing" do
      meeting = insert(:meeting, location: "Room A\nX-Injected: evil-header")

      text = VideoRoomFailed.render_text(meeting)

      assert text =~ "Video Setup Failed"
      assert text =~ "Location: Room A"
    end
  end
end
