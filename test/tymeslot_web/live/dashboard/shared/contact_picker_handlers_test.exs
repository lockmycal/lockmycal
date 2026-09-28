defmodule TymeslotWeb.Dashboard.Shared.ContactPickerHandlersTest do
  @moduledoc """
  Covers `ContactPickerHandlers.query/3`'s result cap — moved from a
  post-query `Enum.take/2` to `Contacts.list_contacts/2`'s `opts[:limit]`,
  so the dropdown's 8-result cap is now enforced by the database query
  itself instead of discarding rows Elixir already fetched.
  """

  use Tymeslot.DataCase, async: true

  @moduletag :contacts
  @moduletag :live

  import Tymeslot.Factory

  alias TymeslotWeb.Dashboard.Shared.ContactPickerHandlers

  defp socket_with_defaults do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        contact_picker_query: "",
        contact_picker_open: false,
        contact_picker_results: []
      }
    }
  end

  describe "query/3" do
    test "caps results at 8 even when more contacts match" do
      user = insert(:user)
      for n <- 1..10, do: insert(:contact, organizer_user: user, name: "Match #{n}")

      {:noreply, socket} =
        ContactPickerHandlers.query(%{"query" => "Match"}, socket_with_defaults(), user.id)

      assert length(socket.assigns.contact_picker_results) == 8
    end

    test "opens the dropdown and stores the query term" do
      user = insert(:user)
      insert(:contact, organizer_user: user, name: "Ada Lovelace")

      {:noreply, socket} =
        ContactPickerHandlers.query(%{"query" => "ada"}, socket_with_defaults(), user.id)

      assert socket.assigns.contact_picker_open
      assert socket.assigns.contact_picker_query == "ada"
      assert [%{name: "Ada Lovelace"}] = socket.assigns.contact_picker_results
    end
  end
end
