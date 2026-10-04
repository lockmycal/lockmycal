defmodule TymeslotWeb.Dashboard.BookingsAttendingTest do
  @moduledoc """
  A request the user sent on someone else's booking page, on their own
  Meetings page: badged as waiting on the host, with nothing to approve or
  decline, since only its organiser answers it.
  """

  use TymeslotWeb.LiveCase, async: false

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  @moduletag :live
  @moduletag :bookings
  @moduletag :meetings

  alias Plug.Test

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    insert(:profile, user: user)

    conn = conn |> Test.init_test_session(%{}) |> fetch_session() |> log_in_user(user)
    {:ok, conn: conn, user: user}
  end

  defp held(attrs) do
    start = DateTime.add(DateTime.utc_now(:second), 5, :day)

    insert(
      :meeting,
      Map.merge(
        %{
          status: "awaiting_approval",
          start_time: start,
          end_time: DateTime.add(start, 30, :minute),
          approval_requested_at: DateTime.utc_now(:second),
          approval_deadline_at: DateTime.add(DateTime.utc_now(:second), 24, :hour)
        },
        attrs
      )
    )
  end

  defp open_requests(conn) do
    {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
    render_click(element(view, "button", "Requests"))
    view
  end

  test "a request the user sent waits on the host, with nothing for them to answer",
       %{conn: conn, user: user} do
    host = insert(:user)

    sent =
      held(%{
        organizer_user_id: host.id,
        organizer_email: host.email,
        attendee_email: user.email,
        booker_user_id: user.id
      })

    view = open_requests(conn)

    assert render(view) =~ "Awaiting host approval"
    refute has_element?(view, "#approve-request-#{sent.id}")
  end

  test "a booking the user made elsewhere is shown from their side", %{conn: conn, user: user} do
    host = insert(:user)
    start = DateTime.add(DateTime.utc_now(:second), 5, :day)

    booked =
      insert(:meeting,
        status: "confirmed",
        start_time: start,
        end_time: DateTime.add(start, 30, :minute),
        organizer_user_id: host.id,
        organizer_email: host.email,
        organizer_name: "Jana Host",
        attendee_email: user.email,
        attendee_name: "Me Myself",
        attendee_phone: "+420111222333",
        meeting_url: "https://video.example.com/room",
        attendee_video_url: "https://video.example.com/attendee",
        booker_user_id: user.id
      )

    {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
    html = render(view)

    assert html =~ "Jana Host"
    # The host shared neither their email nor their phone.
    refute html =~ host.email
    refute html =~ "Me Myself"
    refute html =~ "+420111222333"
    assert has_element?(view, "a[href='https://video.example.com/attendee']")

    # The host's actions are not theirs; cancelling their booking is.
    refute has_element?(view, "#add-guests-#{booked.id}")

    refute has_element?(
             view,
             "button[phx-click='show_reschedule_modal'][phx-value-id='#{booked.id}']"
           )

    assert has_element?(view, "#cancel-meeting-#{booked.id}")
  end

  test "shows the host's email and phone the host shared", %{conn: conn, user: user} do
    host = insert(:user)
    start = DateTime.add(DateTime.utc_now(:second), 5, :day)

    insert(:meeting,
      status: "confirmed",
      start_time: start,
      end_time: DateTime.add(start, 30, :minute),
      organizer_user_id: host.id,
      organizer_email: host.email,
      attendee_email: user.email,
      share_organizer_email: true,
      organizer_phone: "+420777888999"
    )

    {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")
    html = render(view)

    assert html =~ "Host Email"
    assert html =~ host.email
    assert html =~ "Host Phone"
    assert html =~ "+420777888999"
  end

  test "a request the user received still offers approve and decline", %{
    conn: conn,
    user: user
  } do
    received =
      held(%{
        organizer_user_id: user.id,
        organizer_email: user.email,
        attendee_email: "guest@example.com"
      })

    view = open_requests(conn)

    assert render(view) =~ "Awaiting your approval"
    assert has_element?(view, "#approve-request-#{received.id}")
  end
end
