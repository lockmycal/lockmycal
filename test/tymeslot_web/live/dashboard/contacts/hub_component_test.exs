defmodule TymeslotWeb.Dashboard.Contacts.HubComponentTest do
  @moduledoc """
  End-to-end coverage of the Contacts dashboard page: list, search,
  create/edit/delete, and the note indicator.
  """
  use TymeslotWeb.LiveCase, async: false

  @moduletag :contacts
  @moduletag :live

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory
  import Tymeslot.TestFixtures

  alias Plug.Test, as: PlugTest
  alias Tymeslot.ConfigTestHelpers
  alias Tymeslot.Contacts
  alias Tymeslot.Onboarding.OnboardingQueries
  alias Tymeslot.Profiles

  setup %{conn: conn} do
    user = create_user_fixture()
    {:ok, user} = OnboardingQueries.mark_onboarding_complete(user)
    profile = Profiles.get_profile(user.id)
    {:ok, profile} = Profiles.update_profile_field(profile, :contacts_enabled, true)

    ConfigTestHelpers.setup_config(:tymeslot,
      feature_access_checker: Tymeslot.Features.DefaultAccessChecker,
      dashboard_additional_hooks: [],
      feature_placeholder_components: %{}
    )

    conn = conn |> PlugTest.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user, profile: profile}
  end

  describe "list" do
    test "shows an empty state when there are no contacts", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/contacts")

      assert html =~ "No contacts yet"
    end

    test "lists existing contacts and shows a note indicator", %{conn: conn, user: user} do
      insert(:contact, organizer_user: user, name: "Jane Booker", note: "Prefers mornings")
      insert(:contact, organizer_user: user, name: "Bob Smith", note: nil)

      {:ok, _view, html} = live(conn, ~p"/dashboard/contacts")

      assert html =~ "Jane Booker"
      assert html =~ "Bob Smith"
      assert html =~ "Prefers mornings"
    end

    test "search filters the list by name or email", %{conn: conn, user: user} do
      insert(:contact, organizer_user: user, name: "Jane Booker", email: "jane@example.com")
      insert(:contact, organizer_user: user, name: "Bob Smith", email: "bob@acme.com")

      {:ok, view, _html} = live(conn, ~p"/dashboard/contacts")

      html =
        view
        |> form("#contacts-search-form", %{"term" => "jane"})
        |> render_change()

      assert html =~ "Jane Booker"
      refute html =~ "Bob Smith"
    end
  end

  describe "pagination" do
    test "shows 20 contacts per page, pages on, and switches the page size", %{
      conn: conn,
      user: user
    } do
      for n <- 1..25 do
        insert(:contact,
          organizer_user: user,
          name: "Contact #{String.pad_leading("#{n}", 2, "0")}",
          email: "contact#{n}@example.com"
        )
      end

      {:ok, view, html} = live(conn, ~p"/dashboard/contacts")

      assert html =~ "1–20 of 25"
      assert html =~ "Contact 20"
      refute html =~ "Contact 21"

      html = view |> element("#contacts-pagination button", "2") |> render_click()
      assert html =~ "21–25 of 25"
      assert html =~ "Contact 21"
      refute html =~ "Contact 20"

      html =
        view
        |> form("#contacts-pagination-per-page-form", contacts_paging: %{per_page: "50"})
        |> render_change()

      assert html =~ "1–25 of 25"
      assert html =~ "Contact 01"
      assert html =~ "Contact 25"
    end
  end

  describe "create" do
    test "adds a contact via the form", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/contacts")

      view
      |> element("button", "Add contact")
      |> render_click()

      html =
        view
        |> form("#contact-form", %{
          "contact" => %{
            "name" => "Jane Booker",
            "email" => "jane@example.com",
            "phone" => "555-1234",
            "company" => "Acme",
            "note" => "Met at a conference"
          }
        })
        |> render_submit()

      assert html =~ "Jane Booker"
      assert [contact] = Contacts.list_contacts(user.id)
      assert contact.email == "jane@example.com"
      assert contact.note == "Met at a conference"
    end
  end

  describe "edit" do
    test "updates an existing contact", %{conn: conn, user: user} do
      contact = insert(:contact, organizer_user: user, name: "Old Name")

      {:ok, view, _html} = live(conn, ~p"/dashboard/contacts")

      view
      |> element("button[aria-label='Edit contact']")
      |> render_click()

      html =
        view
        |> form("#contact-form", %{
          "contact" => %{
            "name" => "New Name",
            "email" => contact.email,
            "phone" => "",
            "company" => "",
            "note" => ""
          }
        })
        |> render_submit()

      assert html =~ "New Name"
      assert {:ok, updated} = Contacts.get_contact(contact.id, user.id)
      assert updated.name == "New Name"
    end
  end

  describe "delete" do
    test "removes a contact after confirming the modal", %{conn: conn, user: user} do
      contact = insert(:contact, organizer_user: user, name: "Delete Me")

      {:ok, view, _html} = live(conn, ~p"/dashboard/contacts")

      view
      |> element("button[aria-label='Delete contact']")
      |> render_click()

      html =
        view
        |> element("button", "Delete Contact")
        |> render_click()

      refute html =~ "Delete Me"
      assert Contacts.get_contact(contact.id, user.id) == {:error, :not_found}
    end
  end

  describe "sidebar visibility" do
    test "shows the Contacts link when collection is enabled", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

      assert html =~ ~s(href="/dashboard/contacts")
    end

    # contacts_enabled is the per-user auto-capture opt-in, not the plan gate
    # (:contacts_allowed): per Tymeslot.Contacts' own moduledoc the two are
    # independent, and disabling auto-capture must never block manual
    # CRUD/reading of contacts already captured — so the nav link itself
    # stays visible (same as Automation/Analytics, gated only by the plan
    # flag) even with collection turned off.
    test "still shows the Contacts link when collection is disabled — that flag only gates auto-capture, not manual access",
         %{conn: conn, profile: profile} do
      {:ok, _profile} = Profiles.update_profile_field(profile, :contacts_enabled, false)

      {:ok, _view, html} = live(conn, ~p"/dashboard/overview")

      assert html =~ ~s(href="/dashboard/contacts")
    end
  end
end
