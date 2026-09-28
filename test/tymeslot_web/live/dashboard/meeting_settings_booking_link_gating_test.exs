defmodule TymeslotWeb.Dashboard.MeetingSettingsBookingLinkGatingTest do
  @moduledoc """
  Verifies the UI side of `:custom_booking_link_allowed` gating on the
  meeting-type "Change link" action — the disabled button + Pro badge.
  Server-side defense-in-depth against a stale/hand-crafted event is covered
  by `TymeslotWeb.Dashboard.ServiceSettingsComponentTest`, and backend
  enforcement itself by `Tymeslot.MeetingTypes.SlugGatingTest`.
  """

  # async: false — mutates the global :feature_assigns application env, same
  # reasoning as test/tymeslot/profiles/username_gating_test.exs.
  use TymeslotWeb.LiveCase, async: false

  @moduletag :meeting_types
  @moduletag :live

  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Ecto.Changeset
  alias Tymeslot.Repo

  setup :setup_dashboard_user

  setup %{profile: profile} do
    # The link/visibility controls only appear once the profile has a
    # username, same as the "Booking link and visibility" describe block in
    # meeting_settings_test.exs.
    %{profile: Repo.update!(Changeset.change(profile, username: "linkhost"))}
  end

  setup do
    previous = Application.get_env(:tymeslot, :feature_assigns, [])
    on_exit(fn -> Application.put_env(:tymeslot, :feature_assigns, previous) end)
    :ok
  end

  defp lock_custom_booking_link do
    previous = Application.get_env(:tymeslot, :feature_assigns, [])

    Application.put_env(
      :tymeslot,
      :feature_assigns,
      Keyword.put(previous, :custom_booking_link_allowed, false)
    )
  end

  describe "Change link button when custom_booking_link_allowed is false" do
    test "renders disabled with a Pro badge", %{conn: conn, user: user} do
      meeting_type =
        insert(:meeting_type, user: user, name: "Strategy Session", slug: "original-slug")

      lock_custom_booking_link()

      {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

      view
      |> element("[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
      |> render_click()

      assert has_element?(view, "[data-testid='booking-link-pro-badge']")
      assert has_element?(view, "button[phx-click='open_slug_modal'][disabled]")

      # Phoenix.LiveViewTest itself refuses to click a disabled element, which
      # already demonstrates the client-side lock; the equivalent server-side
      # defense-in-depth (a stale client/hand-crafted event) is exercised
      # directly against the LiveComponent in ServiceSettingsComponentTest.
      assert Repo.reload!(meeting_type).slug == "original-slug"
    end
  end
end
