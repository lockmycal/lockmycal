defmodule TymeslotWeb.Components.Dashboard.ContactPicker do
  @moduledoc """
  Small type-to-filter dropdown for picking an existing `Tymeslot.Contacts`
  entry, shared by the calendar's "Quick add" meeting dialog
  (`TymeslotWeb.Dashboard.CalendarGrid.Modals.CreateEventModal`) and the
  Meetings page's own quick-add dialog
  (`TymeslotWeb.Components.Dashboard.Meetings.CreateMeetingModal`).

  Purely presentational: the parent LiveComponent owns the `query`/`open`/
  `contacts` assigns (via `TymeslotWeb.Dashboard.Shared.ContactPickerHandlers`)
  and handles the `select_event` push itself, since what selecting a contact
  fills in differs per form.

  Built on `CoreComponents.Dropdown` with `trigger_wrapper={:none}`: this is
  a type-ahead combobox (typing opens/filters the panel) rather than the
  click-to-open menu `Dropdown` normally wraps in a `<button>`, so the search
  form is the trigger slot's own markup instead.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Dashboard.SearchInput

  attr :id, :string, required: true
  attr :contacts, :list, required: true
  attr :query, :string, default: ""
  attr :open, :boolean, default: false
  attr :target, :any, required: true
  attr :query_event, :string, required: true
  attr :select_event, :string, required: true
  attr :close_event, :string, required: true
  attr :placeholder, :string, default: nil
  attr :icon, :string, default: "hero-identification", doc: "the search field's leading icon"

  @spec contact_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def contact_picker(assigns) do
    ~H"""
    <.dropdown
      id={"#{@id}-dropdown"}
      open={@open}
      on_close={@close_event}
      target={@target}
      trigger_wrapper={:none}
      position={:bottom_start}
      role="listbox"
      class="w-full max-h-56 overflow-y-auto bg-white dark:bg-twilight-indigo-900 border border-neutral-300 dark:border-twilight-indigo-700 rounded-xl shadow-lg py-1"
    >
      <:trigger>
        <SearchInput.search_input
          form_id={"#{@id}-form"}
          input_id={@id}
          name="query"
          value={@query}
          change_event={@query_event}
          target={@target}
          debounce="200"
          icon={@icon}
          placeholder={@placeholder || dgettext("dashboard_common", "Pick from contacts")}
        />
      </:trigger>
      <:panel>
        <button
          :for={contact <- @contacts}
          type="button"
          phx-click={@select_event}
          phx-value-id={contact.id}
          phx-target={@target}
          class="w-full text-left px-3 py-2 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 focus:outline-hidden focus:bg-neutral-50 dark:focus:bg-twilight-indigo-800"
          role="option"
        >
          <span class="block text-token-sm text-neutral-800 dark:text-neutral-100 truncate">{contact.name}</span>
          <span class="block text-token-xs text-neutral-500 dark:text-twilight-indigo-300 truncate">{contact.email}</span>
        </button>
        <p
          :if={@contacts == []}
          class="px-3 py-2 text-token-sm text-neutral-400 dark:text-twilight-indigo-300"
        >
          {dgettext("dashboard_common", "No matching contacts")}
        </p>
      </:panel>
    </.dropdown>
    """
  end
end
