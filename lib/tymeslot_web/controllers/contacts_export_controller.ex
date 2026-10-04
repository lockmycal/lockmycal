defmodule TymeslotWeb.ContactsExportController do
  @moduledoc """
  Downloads the signed-in organizer's contacts as a CSV file
  (`Tymeslot.Contacts.export_csv/2`), limited to those matching the Contacts
  page's search when `search` is given.

  Behind the authenticated dashboard pipeline and always scoped to the
  signed-in user; sent as a download with `nosniff` and `no-store`, since the
  file holds personal data.
  """

  use TymeslotWeb, :controller

  alias Tymeslot.Contacts

  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, params) do
    user = conn.assigns.current_user
    search = search_term(params)
    filename = "contacts-#{Date.to_iso8601(Date.utc_today())}.csv"

    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_download({:binary, Contacts.export_csv(user.id, search)},
      filename: filename,
      content_type: "text/csv"
    )
  end

  defp search_term(%{"search" => search}) when is_binary(search), do: search
  defp search_term(_params), do: ""
end
