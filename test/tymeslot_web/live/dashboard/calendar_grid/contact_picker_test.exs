defmodule TymeslotWeb.Dashboard.CalendarGrid.ContactPickerTest do
  @moduledoc """
  Covers the "pick from contacts" shortcut on the calendar Quick add modal's
  meeting-mode guest fields.
  """

  # async: false — "is hidden when contacts is not allowed on the plan" below
  # writes the node-wide :feature_assigns application env.
  use TymeslotWeb.LiveCase, async: false

  @moduletag :calendar
  @moduletag :live

  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  alias Plug.Test

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now())
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")
    conn = conn |> Test.init_test_session(%{}) |> fetch_session()
    conn = log_in_user(conn, user)
    {:ok, conn: conn, user: user}
  end

  defp open_create_form(lv) do
    lv
    |> element("#calendar-grid")
    |> render_hook("show_create_form", %{})
  end

  describe "guest contact picker" do
    test "renders in meeting mode", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      html = open_create_form(lv)

      assert html =~ ~s(id="create-meeting-contact-picker")
      assert html =~ "Pick from contacts"
    end

    test "is hidden when contacts is not allowed on the plan", %{conn: conn} do
      original = Application.get_env(:tymeslot, :feature_assigns, [])

      Application.put_env(
        :tymeslot,
        :feature_assigns,
        Keyword.put(original, :contacts_allowed, false)
      )

      on_exit(fn -> Application.put_env(:tymeslot, :feature_assigns, original) end)

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      html = open_create_form(lv)

      refute html =~ ~s(id="create-meeting-contact-picker")
    end

    test "typing filters and shows matching contacts", %{conn: conn, user: user} do
      contact =
        insert(:contact, organizer_user: user, name: "Ada Lovelace", email: "ada@example.com")

      insert(:contact, organizer_user: user, name: "Grace Hopper", email: "grace@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      open_create_form(lv)

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("guest_contact_query", %{"query" => "ada"})

      assert html =~ contact.name
      refute html =~ "Grace Hopper"
    end

    test "selecting a contact fills guest name and email", %{conn: conn, user: user} do
      contact =
        insert(:contact, organizer_user: user, name: "Ada Lovelace", email: "ada@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      open_create_form(lv)

      lv
      |> element("#calendar-grid")
      |> render_hook("guest_contact_query", %{"query" => "ada"})

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("select_guest_contact", %{"id" => to_string(contact.id)})

      assert html =~ ~s(value="Ada Lovelace")
      assert html =~ ~s(value="ada@example.com")
      # The dropdown closes after a selection.
      refute html =~ contact.email <> "</span>"
    end

    test "selecting a contact belonging to another organizer is a no-op", %{conn: conn} do
      other_user = insert(:user)
      contact = insert(:contact, organizer_user: other_user, name: "Not Mine")

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      open_create_form(lv)

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("select_guest_contact", %{"id" => to_string(contact.id)})

      refute html =~ ~s(value="Not Mine")
    end

    test "closing the picker hides the dropdown", %{conn: conn, user: user} do
      insert(:contact, organizer_user: user, name: "Ada Lovelace", email: "ada@example.com")

      {:ok, lv, _html} = live(conn, ~p"/dashboard")
      open_create_form(lv)

      lv
      |> element("#calendar-grid")
      |> render_hook("guest_contact_query", %{"query" => "ada"})

      html =
        lv
        |> element("#calendar-grid")
        |> render_hook("close_guest_contact_picker", %{})

      refute html =~ "Ada Lovelace</span>"
    end
  end
end
