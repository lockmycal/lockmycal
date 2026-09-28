defmodule TymeslotWeb.Dashboard.Shared.ContactPickerHandlers do
  @moduledoc """
  Shared `handle_event` logic for the small contact-picker dropdown
  (`TymeslotWeb.Components.Dashboard.ContactPicker`) embedded in both the
  calendar's "Quick add" meeting dialog and the Meetings page's own quick-add
  dialog: type-to-filter against `Tymeslot.Contacts`, capped to a short
  dropdown list.

  Each caller keeps its own `contact_picker_query`/`contact_picker_open`/
  `contact_picker_results` assigns and handles the `select_*_contact` event
  itself, since what selecting a contact fills in differs per form.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.Contacts

  @result_limit 8

  @doc "Handles the picker's `phx-change` query event: filters and reopens the dropdown."
  @spec query(map(), Phoenix.LiveView.Socket.t(), pos_integer()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def query(%{"query" => term}, socket, organizer_user_id) do
    {:noreply,
     socket
     |> assign(:contact_picker_query, term)
     |> assign(:contact_picker_open, true)
     |> assign(:contact_picker_results, search(organizer_user_id, term))}
  end

  @doc "Handles the picker's `phx-click-away` close event."
  @spec close(Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def close(socket), do: {:noreply, assign(socket, :contact_picker_open, false)}

  @doc "Resets the picker to its empty/closed state, e.g. when a contact is selected or the form closes."
  @spec reset(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reset(socket) do
    socket
    |> assign(:contact_picker_query, "")
    |> assign(:contact_picker_open, false)
    |> assign(:contact_picker_results, [])
  end

  defp search(organizer_user_id, term) do
    Contacts.list_contacts(organizer_user_id, search: term, limit: @result_limit)
  end
end
