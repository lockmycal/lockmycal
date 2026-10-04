defmodule TymeslotWeb.ContactsExportControllerTest do
  use TymeslotWeb.ConnCase, async: false

  @moduletag :contacts
  @moduletag :controllers

  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  setup :setup_dashboard_user

  setup %{user: user} do
    insert(:contact, organizer_user: user, name: "Jane Booker", email: "jane@example.com")
    insert(:contact, organizer_user: user, name: "Bob Smith", email: "bob@acme.com")
    insert(:contact, organizer_user: insert(:user), name: "Someone Else")
    :ok
  end

  test "the organizer downloads their own contacts as CSV", %{conn: conn} do
    conn = get(conn, ~p"/dashboard/contacts/export")

    assert conn.status == 200
    assert conn.resp_body =~ "Name,Email,Phone,Company,Note\r\n"
    assert conn.resp_body =~ "Jane Booker,jane@example.com"
    assert conn.resp_body =~ "Bob Smith,bob@acme.com"
    refute conn.resp_body =~ "Someone Else"

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    assert [content_type] = get_resp_header(conn, "content-type")
    assert content_type =~ "text/csv"
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s|attachment; filename="contacts-#{Date.utc_today()}.csv"|
  end

  test "a search exports only the matching contacts", %{conn: conn} do
    conn = get(conn, ~p"/dashboard/contacts/export?#{[search: "acme"]}")

    assert conn.resp_body =~ "Bob Smith"
    refute conn.resp_body =~ "Jane Booker"
  end

  test "a malformed search param exports everything", %{conn: conn} do
    conn = get(conn, "/dashboard/contacts/export?search[x]=1")

    assert conn.status == 200
    assert conn.resp_body =~ "Jane Booker"
  end

  test "a signed-out visitor is sent to log in" do
    conn = get(build_conn(), ~p"/dashboard/contacts/export")
    assert redirected_to(conn) =~ "/auth/login"
  end
end
