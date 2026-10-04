defmodule TymeslotWeb.Live.Themes.ThemeBookingFlowMoreTest do
  use TymeslotWeb.LiveCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo
  @moduletag :utils

  import Mox
  import Phoenix.LiveViewTest
  import Tymeslot.Factory

  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo
  alias Tymeslot.TestMocks

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)

    TestMocks.setup_email_mocks()
    TestMocks.setup_subscription_mocks()

    Tymeslot.CalendarMock
    |> stub(:get_events_for_range_fresh, fn _user_id, _start_date, _end_date -> {:ok, []} end)
    |> stub(:get_booking_integration_info, fn _user_id -> {:error, :no_integration} end)

    :ok
  end

  @themes %{
    "1" => %{name: "quill", duration_selector: "quick-chat"},
    "2" => %{name: "rhythm", duration_selector: "quick-chat"}
  }

  describe "meeting cancel flow (feature-level)" do
    for {theme_id, meta} <- @themes do
      @tag :capture_log
      test "visitor can keep meeting on cancel page with #{meta.name} theme", %{conn: conn} do
        user = insert(:user)

        profile =
          insert(:profile,
            user: user,
            username: "cancel-keep-#{unquote(meta.name)}",
            booking_theme: unquote(theme_id)
          )

        meeting =
          insert(:meeting,
            organizer_user_id: user.id,
            organizer_name: user.name,
            attendee_timezone: profile.timezone,
            status: "confirmed"
          )

        {:ok, view, _html} =
          live(conn, ~p"/#{profile.username}/meeting/#{meeting.uid}/cancel")

        assert has_element?(view, "[data-testid='keep-meeting']")

        view
        |> element("[data-testid='keep-meeting']")
        |> render_click()

        assert render(view) =~ "Meeting Confirmed"
      end

      @tag :capture_log
      test "visitor can cancel meeting from cancel page with #{meta.name} theme", %{conn: conn} do
        user = insert(:user)

        profile =
          insert(:profile,
            user: user,
            username: "cancel-cancel-#{unquote(meta.name)}",
            booking_theme: unquote(theme_id)
          )

        meeting =
          insert(:meeting,
            organizer_user_id: user.id,
            organizer_name: user.name,
            attendee_timezone: profile.timezone,
            status: "confirmed"
          )

        {:ok, view, _html} =
          live(conn, ~p"/#{profile.username}/meeting/#{meeting.uid}/cancel")

        assert has_element?(view, "[data-testid='cancel-meeting']")

        assert {:error, {:redirect, %{to: to}}} =
                 view
                 |> element("[data-testid='cancel-meeting']")
                 |> render_click()

        assert String.contains?(to, "/cancel-confirmed")

        assert Repo.get_by!(MeetingSchema, uid: meeting.uid).status == "cancelled"
      end
    end
  end
end
