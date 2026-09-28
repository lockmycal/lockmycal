defmodule TymeslotWeb.Dashboard.BookingsManagementPendingApprovalTest do
  @moduledoc """
  Covers the meetings dashboard opening straight on the "Awaiting Approval"
  tab when the organiser has a meeting waiting on them.
  """

  use TymeslotWeb.LiveCase, async: true
  @moduletag :meetings
  @moduletag :live

  import Tymeslot.Factory
  import Tymeslot.AuthTestHelpers

  alias Plug.Test

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    _profile = insert(:profile, user: user)
    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user}
  end

  test "opens on the Awaiting Approval tab when a meeting needs approval", %{
    conn: conn,
    user: user
  } do
    insert(:meeting,
      organizer_user: user,
      organizer_email: user.email,
      attendee_name: "Needs A Yes",
      status: "awaiting_approval"
    )

    {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")

    assert render(view) =~ "Needs A Yes"

    # The tab itself is labelled "Requests" (a count badge alongside it, not
    # baked into the label text — unlike the other filter tabs).
    assert has_element?(view, "button[phx-value-filter='awaiting_approval']", "Requests")
    assert has_element?(view, "button[phx-value-filter='awaiting_approval']", "1")
  end

  test "still opens on Upcoming when nothing needs approval", %{conn: conn, user: user} do
    insert(:meeting,
      organizer_user: user,
      organizer_email: user.email,
      attendee_name: "Confirmed Person",
      status: "confirmed"
    )

    {:ok, view, _html} = live(conn, ~p"/dashboard/meetings")

    refute render(view) =~ "Awaiting Approval"
    assert render(view) =~ "Confirmed Person"
  end
end
