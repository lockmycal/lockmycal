defmodule TymeslotWeb.Dashboard.Contacts.ListView do
  @moduledoc """
  Stateless view rendered inside `TymeslotWeb.Dashboard.Contacts.HubComponent`
  when a contact isn't being created/edited: the search + "Add contact"
  toolbar, the contacts table, and its empty state.

  Every interactive element carries `phx-target={@target}` so its events
  reach the hub's own `handle_event/3` rather than the parent LiveView.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Pagination.OffsetPage
  alias TymeslotWeb.Components.Dashboard.Pagination
  alias TymeslotWeb.Components.Dashboard.SearchInput

  attr :contacts, :list, required: true, doc: "the current page's contacts"
  attr :search_term, :string, required: true
  attr :page, :integer, required: true
  attr :per_page, :integer, required: true
  attr :total, :integer, required: true, doc: "contacts matching the search, across all pages"
  attr :total_pages, :integer, required: true
  attr :target, :any, required: true

  @spec list(map()) :: Phoenix.LiveView.Rendered.t()
  def list(assigns) do
    ~H"""
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-3">
      <.subsection_header
        icon="hero-identification"
        title={dgettext("dashboard_contacts", "Contact List")}
        count={@total}
      />

      <div class="flex flex-wrap items-center gap-3">
        <.search_box search_term={@search_term} target={@target} />

        <%!-- Exports what the search matches, across all pages. --%>
        <a
          :if={@total > 0}
          id="contacts-export-csv"
          href={export_path(@search_term)}
          class="btn btn-secondary"
          download
        >
          <.icon name="hero-arrow-down-tray" class="w-5 h-5" />
          {dgettext("dashboard_contacts", "Export CSV")}
        </a>

        <button
          type="button"
          phx-click="new_contact"
          phx-target={@target}
          class="btn btn-primary"
        >
          <.icon name="hero-plus" class="w-5 h-5" />
          {dgettext("dashboard_contacts", "Add contact")}
        </button>
      </div>
    </div>

    <div :if={@contacts != []} class="card-glass p-0! overflow-hidden">
      <table class="min-w-full divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <thead class="bg-neutral-50/60 dark:bg-twilight-indigo-950/60">
          <tr>
            <.th>{dgettext("dashboard_contacts", "Name")}</.th>
            <.th>{dgettext("dashboard_contacts", "Email")}</.th>
            <.th>{dgettext("dashboard_contacts", "Phone")}</.th>
            <.th>{dgettext("dashboard_contacts", "Company")}</.th>
            <.th class="text-right">{dgettext("dashboard_contacts", "Actions")}</.th>
          </tr>
        </thead>
        <tbody class="divide-y divide-neutral-50 dark:divide-twilight-indigo-800">
          <tr
            :for={contact <- @contacts}
            class="hover:bg-neutral-50/40 dark:hover:bg-twilight-indigo-900/40 transition-colors"
          >
            <td class="px-6 py-4 text-sm font-medium text-neutral-900 dark:text-neutral-100">
              <div class="flex items-center gap-1.5">
                {contact.name}
                <.note_indicator :if={present?(contact.note)} note={contact.note} />
              </div>
            </td>
            <td class="px-6 py-4 text-sm text-neutral-700 dark:text-neutral-300">
              {contact.email}
            </td>
            <td class="px-6 py-4 text-sm text-neutral-700 dark:text-neutral-300">
              <span :if={present?(contact.phone)}>{contact.phone}</span>
              <span :if={!present?(contact.phone)} class="text-neutral-400">—</span>
            </td>
            <td class="px-6 py-4 text-sm text-neutral-700 dark:text-neutral-300">
              <span :if={present?(contact.company)}>{contact.company}</span>
              <span :if={!present?(contact.company)} class="text-neutral-400">—</span>
            </td>
            <td class="px-6 py-4">
              <.row_actions contact={contact} target={@target} />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Pagination.pagination
      :if={@total > 0}
      id="contacts-pagination"
      class="mt-4"
      page={@page}
      total_pages={@total_pages}
      total={@total}
      per_page={@per_page}
      per_page_options={OffsetPage.page_sizes()}
      page_event="page"
      per_page_event="per_page"
      per_page_param="contacts_paging"
      target={@target}
    />

    <div :if={@contacts == [] and @search_term == ""} class="card-glass p-10 text-center">
      <div class="mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-token-2xl bg-primary-50 text-primary-500">
        <.icon name="hero-identification" class="w-7 h-7" />
      </div>
      <h3 class="text-token-lg font-semibold text-neutral-800 dark:text-neutral-100">
        {dgettext("dashboard_contacts", "No contacts yet")}
      </h3>
      <p class="mt-1 text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
        {dgettext(
          "dashboard_contacts",
          "Contacts from new bookings will appear here, or add one manually."
        )}
      </p>
    </div>

    <div :if={@contacts == [] and @search_term != ""} class="card-glass p-10 text-center">
      <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
        {dgettext("dashboard_contacts", "No contacts match your search.")}
      </p>
    </div>
    """
  end

  attr :search_term, :string, required: true
  attr :target, :any, required: true

  defp search_box(assigns) do
    ~H"""
    <SearchInput.search_input
      form_id="contacts-search-form"
      input_id="contacts-search-input"
      value={@search_term}
      change_event="search"
      target={@target}
      placeholder={dgettext("dashboard_contacts", "Search contacts")}
      input_class="w-full sm:w-64"
    />
    """
  end

  attr :note, :string, required: true

  defp note_indicator(assigns) do
    ~H"""
    <span title={@note} class="text-primary-500 shrink-0">
      <.icon name="hero-chat-bubble-left-ellipsis-mini" class="w-4 h-4" />
    </span>
    """
  end

  attr :contact, :map, required: true
  attr :target, :any, required: true

  defp row_actions(assigns) do
    ~H"""
    <div class="flex items-center justify-end gap-1">
      <button
        type="button"
        phx-click="edit_contact"
        phx-value-id={@contact.id}
        phx-target={@target}
        class="row-action-button row-action-button--icon-only row-action-button--neutral"
        title={dgettext("dashboard_contacts", "Edit contact")}
        aria-label={dgettext("dashboard_contacts", "Edit contact")}
      >
        <.icon name="hero-pencil-square" class="w-5 h-5" />
      </button>

      <button
        type="button"
        phx-click="view_meetings"
        phx-value-id={@contact.id}
        phx-target={@target}
        class="row-action-button row-action-button--icon-only row-action-button--neutral"
        title={dgettext("dashboard_contacts", "View meetings")}
        aria-label={dgettext("dashboard_contacts", "View meetings")}
      >
        <.icon name="hero-calendar-days" class="w-5 h-5" />
      </button>

      <button
        type="button"
        phx-click="show_delete_modal"
        phx-value-id={@contact.id}
        phx-target={@target}
        class="row-action-button row-action-button--danger"
        title={dgettext("dashboard_contacts", "Delete contact")}
        aria-label={dgettext("dashboard_contacts", "Delete contact")}
      >
        <.icon name="hero-trash" class="w-5 h-5" />
      </button>
    </div>
    """
  end

  attr :class, :string, default: ""
  slot :inner_block, required: true

  defp th(assigns) do
    ~H"""
    <th
      scope="col"
      class={[
        "px-6 py-3 text-left text-xs font-black uppercase tracking-wider text-neutral-500 dark:text-neutral-400",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </th>
    """
  end

  defp export_path(""), do: ~p"/dashboard/contacts/export"
  defp export_path(search_term), do: ~p"/dashboard/contacts/export?#{[search: search_term]}"

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_value), do: true
end
