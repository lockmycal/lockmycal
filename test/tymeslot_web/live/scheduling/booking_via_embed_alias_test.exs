defmodule TymeslotWeb.Live.Scheduling.BookingViaEmbedAliasTest do
  @moduledoc """
  A booking made through the widget's hidden address (`/_…`) keeps the
  address hidden after the booking too: the meeting's view, reschedule and
  cancel links, which every booking email carries, are stored under the
  alias rather than the username. A booking from the public page keeps the
  username. Replacing or removing the alias ends those links, as it ends the
  widget code that uses it.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :integration
  @moduletag :bookings
  @moduletag :scheduling
  @moduletag :live

  import Mox
  import Tymeslot.Factory

  alias Ecto.Changeset
  alias Tymeslot.BookingTestHelpers
  alias Tymeslot.Infrastructure.AvailabilityCache
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.TestMocks

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)
    RateLimiter.clear_all()
    AvailabilityCache.clear_all()

    # Submitting without a reCAPTCHA token; the gate is orthogonal to the links.
    old_cfg = Application.get_env(:tymeslot, :recaptcha, [])
    Application.put_env(:tymeslot, :recaptcha, Keyword.put(old_cfg, :booking_enabled, false))
    on_exit(fn -> Application.put_env(:tymeslot, :recaptcha, old_cfg) end)

    TestMocks.setup_all_mocks()

    user = insert(:user)

    profile =
      user
      |> BookingTestHelpers.bookable_profile("1", "alias-host")
      |> Changeset.change(embed_alias: "_hiddenhost")
      |> Repo.update!()

    insert(:meeting_type, user: user, duration_minutes: 30, name: "Intro", is_active: true)

    %{profile: profile}
  end

  @tag :capture_log
  test "a booking through the hidden address gets its links under it", %{
    conn: conn,
    profile: profile
  } do
    meeting = book(conn, profile, "/_hiddenhost", "alias@example.com")

    for url <- [meeting.view_url, meeting.reschedule_url, meeting.cancel_url] do
      assert URI.parse(url).path =~ ~r{^/_hiddenhost/meeting/}
      refute url =~ "alias-host"
    end
  end

  @tag :capture_log
  test "the cancel and reschedule links under the hidden address open their pages", %{
    conn: conn,
    profile: profile
  } do
    meeting = book(conn, profile, "/_hiddenhost", "links@example.com")

    for url <- [meeting.cancel_url, meeting.reschedule_url] do
      assert {:ok, _view, _html} = live(conn, URI.parse(url).path)
    end
  end

  @tag :capture_log
  test "after the address is replaced, the old links stop working", %{
    conn: conn,
    profile: profile
  } do
    meeting = book(conn, profile, "/_hiddenhost", "replaced@example.com")
    profile |> Changeset.change(embed_alias: "_newaddress") |> Repo.update!()

    assert_error_sent 404, fn -> get(conn, URI.parse(meeting.cancel_url).path) end
  end

  @tag :capture_log
  test "a booking from the public page keeps the username", %{conn: conn, profile: profile} do
    meeting = book(conn, profile, "/alias-host", "public@example.com")

    assert URI.parse(meeting.view_url).path =~ ~r{^/alias-host/meeting/}
  end

  defp book(conn, profile, path, email) do
    {:ok, view, _html} = live(conn, "#{path}?timezone=#{profile.timezone}")
    view = BookingTestHelpers.walk_to_booking_form(view, profile.timezone)

    view
    |> form("#booking-form", %{
      "booking" => %{
        "name" => "Ada Lovelace",
        "email" => email,
        "phone" => "+1 555 200 3000",
        "message" => "Booked through the widget"
      }
    })
    |> render_submit()

    _drain = :sys.get_state(view.pid)

    assert [meeting] = Repo.all_by(MeetingSchema, attendee_email: email)
    meeting
  end
end
