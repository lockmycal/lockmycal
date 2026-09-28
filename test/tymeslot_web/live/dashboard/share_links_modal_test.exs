defmodule TymeslotWeb.Dashboard.ShareLinksModalTest do
  @moduledoc """
  The dashboard-wide "Send links by email" dialog
  (`TymeslotWeb.Dashboard.Shared.ShareLinksModalComponent`) and its three
  entry points: the sidebar, the Overview card and the meeting types page.
  """

  use TymeslotWeb.LiveCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :live
  @moduletag :dashboard

  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  alias Ecto.Changeset
  alias Tymeslot.Repo
  alias Tymeslot.ShareLinks
  alias Tymeslot.Workers.EmailWorker

  setup :setup_dashboard_user

  describe "with a username and a connected calendar" do
    setup %{user: user, profile: profile} do
      insert(:calendar_integration, user: user)
      %{profile: Repo.update!(Changeset.change(profile, username: "sharehost"))}
    end

    test "the Overview card opens the dialog with the booking page pre-selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      refute has_element?(view, "#share-links-form")

      view |> element("#overview-email-booking-link") |> render_click()

      assert has_element?(view, "#share-links-form")
      assert has_element?(view, "#share-links-link-booking_page[checked]")
      refute has_element?(view, "#share-links-link-calendar[checked]")
    end

    test "the sidebar button opens the dialog", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      view |> element("#email-scheduling-link") |> render_click()

      assert has_element?(view, "#share-links-form")
    end

    test "a meeting type's button pre-selects that meeting type only", %{conn: conn, user: user} do
      meeting_type = insert(:meeting_type, user: user, name: "Intro call")
      dom_key = "meeting_type-#{meeting_type.id}"

      {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

      view |> element("#email-meeting-type-link-#{meeting_type.id}") |> render_click()

      assert has_element?(view, "#share-links-link-#{dom_key}[checked]")
      refute has_element?(view, "#share-links-link-booking_page[checked]")
    end

    test "sending enqueues one email per recipient and confirms", %{conn: conn, user: user} do
      meeting_type = insert(:meeting_type, user: user, name: "Intro call")
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      view |> element("#overview-email-booking-link") |> render_click()

      view
      |> form("#share-links-form",
        share: %{
          recipients: "a@example.com, b@example.com",
          links: ["calendar", ShareLinks.meeting_type_key(meeting_type)],
          message: "See you soon"
        }
      )
      |> render_submit()

      assert render(view) =~ "Links sent to 2 recipients."
      refute has_element?(view, "#share-links-form")

      for recipient <- ["a@example.com", "b@example.com"] do
        assert_enqueued(
          worker: EmailWorker,
          args: %{
            "action" => "send_share_links",
            "recipient_email" => recipient,
            "link_keys" => ["calendar", ShareLinks.meeting_type_key(meeting_type)],
            "message" => "See you soon"
          }
        )
      end
    end

    test "an invalid address keeps the dialog open with an error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

      view |> element("#overview-email-booking-link") |> render_click()

      html =
        view
        |> form("#share-links-form", share: %{recipients: "not-an-address"})
        |> render_submit()

      assert html =~ "Invalid email address: not-an-address"
      assert has_element?(view, "#share-links-form")
      assert all_enqueued(worker: EmailWorker) == []
    end
  end

  test "nothing is offered before a calendar is connected", %{conn: conn, profile: profile} do
    Repo.update!(Changeset.change(profile, username: "sharehost"))

    {:ok, view, _html} = live(conn, ~p"/dashboard/overview")

    refute has_element?(view, "#share-links-modal")
    refute has_element?(view, "#overview-email-booking-link")
    refute has_element?(view, "#email-scheduling-link")
  end
end
