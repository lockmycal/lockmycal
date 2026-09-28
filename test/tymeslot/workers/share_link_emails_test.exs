defmodule Tymeslot.Workers.ShareLinkEmailsTest do
  @moduledoc """
  Covers the `send_share_links` EmailWorker action and the email it renders.
  """

  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :workers
  @moduletag :emails

  import Swoosh.TestAssertions
  import Tymeslot.Factory

  alias Tymeslot.MeetingTypes
  alias Tymeslot.ShareLinks
  alias Tymeslot.Utils.UrlBuilder
  alias Tymeslot.Workers.EmailWorker

  # Delivery runs inside the CircuitBreaker GenServer; global mode routes the
  # test adapter's {:email, _} message back to this process.
  setup :set_swoosh_global

  setup do
    user = insert(:user, email: "alice@example.com", locale: "en")
    profile = insert(:profile, user: user, username: "alice", full_name: "Alice Host")
    meeting_type = insert(:meeting_type, user: user, name: "Intro call", slug: "intro-call")

    %{user: user, profile: profile, meeting_type: meeting_type}
  end

  defp args(user, keys, message \\ "") do
    %{
      "action" => "send_share_links",
      "user_id" => user.id,
      "recipient_email" => "guest@example.com",
      "link_keys" => keys,
      "message" => message
    }
  end

  test "mails the selected links to the recipient, replying to the host", %{
    user: user,
    meeting_type: meeting_type
  } do
    keys = ["booking_page", ShareLinks.meeting_type_key(meeting_type)]

    assert :ok = perform_job(EmailWorker, args(user, keys, "Looking forward <b>to it</b>"))

    assert_receive {:email, email}, 1000
    assert [{_name, "guest@example.com"}] = email.to
    assert {"Alice Host", "alice@example.com"} = email.reply_to
    assert email.subject =~ "Alice Host"

    for body <- [email.html_body, email.text_body] do
      assert body =~ UrlBuilder.booking_url("alice")
      assert body =~ UrlBuilder.meeting_type_url("alice", "intro-call")
      refute body =~ UrlBuilder.public_calendar_url("alice")
    end

    assert email.html_body =~ "Looking forward &lt;b&gt;to it&lt;/b&gt;"
    refute email.html_body =~ "<b>to it</b>"
  end

  test "drops a meeting type deactivated after the send was requested", %{
    user: user,
    meeting_type: meeting_type
  } do
    {:ok, _updated} = MeetingTypes.toggle_meeting_type_status(meeting_type, %{is_active: false})

    assert :ok =
             perform_job(
               EmailWorker,
               args(user, ["calendar", ShareLinks.meeting_type_key(meeting_type)])
             )

    assert_receive {:email, email}, 1000
    assert email.text_body =~ UrlBuilder.public_calendar_url("alice")
    refute email.text_body =~ "intro-call"
  end

  test "discards the job when none of the links exist any more", %{
    user: user,
    meeting_type: meeting_type
  } do
    {:ok, _updated} = MeetingTypes.toggle_meeting_type_status(meeting_type, %{is_active: false})

    assert {:discard, _reason} =
             perform_job(EmailWorker, args(user, [ShareLinks.meeting_type_key(meeting_type)]))

    refute_receive {:email, _email}, 200
  end
end
