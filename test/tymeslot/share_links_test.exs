defmodule Tymeslot.ShareLinksTest do
  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :emails
  @moduletag :scheduling

  import Tymeslot.Factory

  alias Tymeslot.ShareLinks
  alias Tymeslot.Utils.UrlBuilder
  alias Tymeslot.Workers.EmailWorker

  @ready %{has_calendar: true}

  setup do
    user = insert(:user)
    profile = insert(:profile, user: user, username: "alice")
    active = insert(:meeting_type, user: user, name: "Intro call", slug: "intro-call")
    inactive = insert(:meeting_type, user: user, name: "Old", is_active: false)

    %{user: user, profile: profile, active: active, inactive: inactive}
  end

  describe "links_for/1" do
    test "lists the booking page, the public calendar and active meeting types only", %{
      profile: profile,
      active: active,
      inactive: inactive
    } do
      links = ShareLinks.links_for(profile)

      assert Enum.map(links, & &1.key) ==
               ["booking_page", "calendar", ShareLinks.meeting_type_key(active)]

      refute Enum.any?(links, &(&1.key == ShareLinks.meeting_type_key(inactive)))

      assert Enum.map(links, & &1.url) == [
               UrlBuilder.booking_url("alice"),
               UrlBuilder.public_calendar_url("alice"),
               UrlBuilder.meeting_type_url("alice", "intro-call")
             ]
    end

    test "leaves out the public calendar when the host switched it off" do
      profile = insert(:profile, username: "bob", public_calendar_enabled: false)

      keys = profile |> ShareLinks.links_for() |> Enum.map(& &1.key)

      assert "booking_page" in keys
      refute "calendar" in keys
    end

    test "is empty for a host without a username" do
      profile = insert(:profile, username: nil)
      assert ShareLinks.links_for(profile) == []
    end
  end

  describe "parse_recipients/1" do
    test "splits on commas, semicolons and whitespace, lower-cases and de-duplicates" do
      assert {:ok, ["a@example.com", "b@example.com"]} =
               ShareLinks.parse_recipients("A@example.com, b@example.com;\na@example.com")
    end

    test "rejects an empty list" do
      assert {:error, :no_recipients} = ShareLinks.parse_recipients("  ,  ")
    end

    test "reports every invalid address" do
      assert {:error, {:invalid_recipients, ["nope", "also@bad"]}} =
               ShareLinks.parse_recipients("ok@example.com nope also@bad")
    end

    test "caps the number of recipients" do
      input = Enum.map_join(1..(ShareLinks.max_recipients() + 1), ",", &"u#{&1}@example.com")
      assert {:error, :too_many_recipients} = ShareLinks.parse_recipients(input)
    end
  end

  describe "send_links/4" do
    test "enqueues one job per recipient with only the resolvable link keys", %{
      user: user,
      profile: profile,
      active: active
    } do
      params = %{
        "recipients" => "x@example.com, y@example.com",
        "links" => ["calendar", ShareLinks.meeting_type_key(active), "https://evil.example"],
        "message" => "  Hi there  "
      }

      assert {:ok, 2} = ShareLinks.send_links(user, profile, @ready, params)

      for recipient <- ["x@example.com", "y@example.com"] do
        assert_enqueued(
          worker: EmailWorker,
          args: %{
            "action" => "send_share_links",
            "user_id" => user.id,
            "recipient_email" => recipient,
            "link_keys" => ["calendar", ShareLinks.meeting_type_key(active)],
            "message" => "Hi there"
          }
        )
      end
    end

    test "refuses when the host cannot share links yet", %{user: user, profile: profile} do
      params = %{"recipients" => "x@example.com", "links" => ["booking_page"]}

      assert {:error, :not_allowed} =
               ShareLinks.send_links(user, profile, %{has_calendar: false}, params)

      assert all_enqueued(worker: EmailWorker) == []
    end

    test "refuses when no selected key resolves to a link", %{
      user: user,
      profile: profile,
      inactive: inactive
    } do
      params = %{
        "recipients" => "x@example.com",
        "links" => [ShareLinks.meeting_type_key(inactive), "bogus"]
      }

      assert {:error, :no_links} = ShareLinks.send_links(user, profile, @ready, params)
    end

    test "refuses an over-long message", %{user: user, profile: profile} do
      params = %{
        "recipients" => "x@example.com",
        "links" => ["booking_page"],
        "message" => String.duplicate("a", ShareLinks.max_message_length() + 1)
      }

      assert {:error, :message_too_long} = ShareLinks.send_links(user, profile, @ready, params)
    end

    test "is rate limited per recipient emailed", %{user: user, profile: profile} do
      recipients = Enum.map_join(1..10, ",", &"u#{&1}@example.com")
      params = %{"recipients" => recipients, "links" => ["booking_page"]}

      assert {:ok, 10} = ShareLinks.send_links(user, profile, @ready, params)
      assert {:ok, 10} = ShareLinks.send_links(user, profile, @ready, params)
      assert {:ok, 10} = ShareLinks.send_links(user, profile, @ready, params)
      assert {:error, :rate_limited} = ShareLinks.send_links(user, profile, @ready, params)
    end
  end
end
