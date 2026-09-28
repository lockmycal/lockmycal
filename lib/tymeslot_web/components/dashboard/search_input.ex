defmodule TymeslotWeb.Components.Dashboard.SearchInput do
  @moduledoc """
  Shared "icon + debounced text input" search box, used by the calendar
  toolbar (`CalendarGrid.Header.SearchBox`), the contacts list
  (`Dashboard.Contacts.ListView`), and — with a different icon and a
  caller-supplied `change_event` — the "pick from contacts" combobox
  (`ContactPicker`).

  Purely presentational: the caller's own `phx-change` handler owns
  filtering/searching; this component only renders the input and debounces
  the change event to the server.
  """

  use TymeslotWeb, :html

  attr :form_id, :string, required: true
  attr :input_id, :string, required: true
  attr :name, :string, default: "term"
  attr :value, :string, default: ""
  attr :change_event, :string, required: true
  attr :target, :any, default: nil
  attr :debounce, :string, default: "300"
  attr :icon, :string, default: "hero-magnifying-glass-mini"
  attr :placeholder, :string, required: true
  attr :input_class, :string, default: "w-full"
  attr :class, :string, default: nil, doc: "Additional classes on the <form> wrapper"

  @spec search_input(map()) :: Phoenix.LiveView.Rendered.t()
  def search_input(assigns) do
    ~H"""
    <form
      id={@form_id}
      phx-change={@change_event}
      phx-target={@target}
      class={["relative", @class]}
    >
      <span class="pointer-events-none absolute inset-y-0 left-2 flex items-center text-neutral-400">
        <.icon name={@icon} class="w-4 h-4" />
      </span>
      <input
        id={@input_id}
        type="text"
        name={@name}
        value={@value}
        autocomplete="off"
        placeholder={@placeholder}
        aria-label={@placeholder}
        phx-debounce={@debounce}
        class={[
          "pl-8 pr-2 py-1.5 text-token-sm text-neutral-700 dark:text-neutral-200 placeholder:text-neutral-400 bg-white dark:bg-twilight-indigo-950 border border-neutral-300 dark:border-twilight-indigo-700 rounded-md focus:outline-hidden focus:ring-2 focus:ring-primary-400 focus:border-primary-400",
          @input_class
        ]}
      />
    </form>
    """
  end
end
