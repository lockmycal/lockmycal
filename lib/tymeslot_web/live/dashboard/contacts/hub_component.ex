defmodule TymeslotWeb.Dashboard.Contacts.HubComponent do
  @moduledoc """
  Contacts dashboard page: a searchable list of bookers (name, email, phone,
  company, note) captured automatically from public bookings or added by
  hand, with edit/view-meetings/delete row actions.

  Owns every event for the page — `ListView` is a stateless view module that
  renders the table, `FormComponent` is swapped in full-page (not a modal)
  for create/edit, same as `AutomationSettingsComponent`/`WebhookFormComponent`.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Contacts
  alias Tymeslot.Contacts.ContactSchema
  alias Tymeslot.Pagination.OffsetPage
  alias Tymeslot.Utils.FormHelpers
  alias TymeslotWeb.Dashboard.Contacts.FormComponent
  alias TymeslotWeb.Dashboard.Contacts.ListView
  alias TymeslotWeb.Dashboard.Contacts.Modals
  alias TymeslotWeb.Live.Shared.FormValidationHelpers

  @editable_fields ~w(name email phone company note)

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(:search_term, "")
     |> assign(:page, 1)
     |> assign(:per_page, OffsetPage.default_page_size())
     |> assign(:show_form, false)
     |> assign(:form_mode, nil)
     |> assign(:contact_being_edited, nil)
     |> assign(:form_values, %{})
     |> assign(:form_errors, %{})
     |> assign(:saving, false)
     |> assign(:contact_to_delete, nil)
     |> assign(:viewing_contact, nil)
     |> assign(:viewing_meetings, [])}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, load_contacts(socket)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="contacts-hub">
      <Modals.delete_contact_modal
        :if={@contact_to_delete}
        contact={@contact_to_delete}
        target={@myself}
      />

      <Modals.meetings_modal
        :if={@viewing_contact}
        contact={@viewing_contact}
        meetings={@viewing_meetings}
        time_format={@time_format}
        target={@myself}
      />

      <div class="space-y-10 pb-20">
        <%= if @show_form do %>
          <div class="animate-in fade-in slide-in-from-bottom-4 duration-500">
            <.live_component
              module={FormComponent}
              id={"contact-form-#{@form_mode}-#{form_component_key(@contact_being_edited)}"}
              mode={@form_mode}
              contact={@contact_being_edited}
              form_values={@form_values}
              form_errors={@form_errors}
              saving={@saving}
              parent_component={@myself}
            />
          </div>
        <% else %>
          <.section_header
            icon="hero-identification"
            title={dgettext("dashboard_contacts", "Contacts")}
            subtitle={
              dgettext(
                "dashboard_contacts",
                "People who booked with you, captured automatically from new bookings."
              )
            }
          />

          <ListView.list
            contacts={@contacts}
            search_term={@search_term}
            page={@page}
            per_page={@per_page}
            total={@total}
            total_pages={@total_pages}
            target={@myself}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp form_component_key(nil), do: "new"
  defp form_component_key(%ContactSchema{id: id}), do: id

  # --- Search ---

  @impl Phoenix.LiveComponent
  def handle_event("search", %{"term" => term}, socket) do
    {:noreply, socket |> assign(:search_term, term) |> assign(:page, 1) |> load_contacts()}
  end

  # --- Paging ---

  def handle_event("page", %{"page" => page}, socket) do
    case OffsetPage.parse_page(page) do
      {:ok, number} -> {:noreply, socket |> assign(:page, number) |> load_contacts()}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("per_page", %{"contacts_paging" => %{"per_page" => per_page}}, socket) do
    case OffsetPage.parse_per_page(per_page) do
      {:ok, size} ->
        {:noreply, socket |> assign(:per_page, size) |> assign(:page, 1) |> load_contacts()}

      :error ->
        {:noreply, socket}
    end
  end

  # --- Form open/close ---

  def handle_event("new_contact", _params, socket) do
    {:noreply, open_form(socket, :create, nil)}
  end

  def handle_event("edit_contact", %{"id" => id}, socket) do
    case get_contact_for_user(socket, id) do
      {:ok, contact} ->
        {:noreply, open_form(socket, :edit, contact)}

      {:error, :not_found} ->
        Flash.error(dgettext("dashboard_contacts", "Contact not found"))
        {:noreply, socket}
    end
  end

  def handle_event("close_form", _params, socket) do
    {:noreply, close_form(socket)}
  end

  # --- Field-level validation on blur ---

  def handle_event("validate_field", %{"field" => field, "value" => value}, socket) do
    form_values = Map.put(socket.assigns.form_values, field, value)
    changeset = build_changeset(socket, form_values)
    atom_field = FormValidationHelpers.atomize_field(field, @editable_fields)

    form_errors =
      FormValidationHelpers.sync_changeset_field_error(
        socket.assigns.form_errors,
        changeset,
        atom_field
      )

    {:noreply,
     socket
     |> assign(:form_values, form_values)
     |> assign(:form_errors, form_errors)}
  end

  # --- Save (create or update) ---

  def handle_event("save_contact", %{"contact" => params}, socket) do
    save_fn =
      case socket.assigns.form_mode do
        :create ->
          user_id = socket.assigns.current_user.id
          &Contacts.create_contact(user_id, &1)

        :edit ->
          &Contacts.update_contact(socket.assigns.contact_being_edited, &1)
      end

    # Contacts.create_contact/2 merges in an atom-keyed :organizer_user_id —
    # Ecto.Changeset.cast/3 rejects a map with mixed atom/string keys, so the
    # string-keyed form params are normalized to atoms first.
    case save_fn.(atomize_contact_params(params)) do
      {:ok, _contact} ->
        Flash.info(save_success_message(socket.assigns.form_mode))
        {:noreply, socket |> close_form() |> load_contacts()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form_errors, FormHelpers.format_changeset_errors(changeset))}

      {:error, reason} ->
        {:noreply, handle_feature_access_error(socket, reason)}
    end
  end

  # --- Delete ---

  def handle_event("show_delete_modal", %{"id" => id}, socket) do
    case get_contact_for_user(socket, id) do
      {:ok, contact} ->
        {:noreply, assign(socket, :contact_to_delete, contact)}

      {:error, :not_found} ->
        Flash.error(dgettext("dashboard_contacts", "Contact not found"))
        {:noreply, socket}
    end
  end

  def handle_event("hide_delete_modal", _params, socket) do
    {:noreply, assign(socket, :contact_to_delete, nil)}
  end

  def handle_event("delete_contact", _params, socket) do
    case socket.assigns.contact_to_delete do
      nil ->
        {:noreply, socket}

      contact ->
        case Contacts.delete_contact(contact) do
          {:ok, _contact} ->
            Flash.info(dgettext("dashboard_contacts", "Contact deleted"))

            {:noreply,
             socket
             |> assign(:contact_to_delete, nil)
             |> load_contacts()}

          {:error, _changeset} ->
            Flash.error(dgettext("dashboard_contacts", "Failed to delete contact"))
            {:noreply, assign(socket, :contact_to_delete, nil)}
        end
    end
  end

  # --- View meetings ---

  def handle_event("view_meetings", %{"id" => id}, socket) do
    case get_contact_for_user(socket, id) do
      {:ok, contact} ->
        meetings =
          Contacts.list_meetings_for_contact(socket.assigns.current_user.id, contact.email)

        {:noreply,
         socket
         |> assign(:viewing_contact, contact)
         |> assign(:viewing_meetings, meetings)}

      {:error, :not_found} ->
        Flash.error(dgettext("dashboard_contacts", "Contact not found"))
        {:noreply, socket}
    end
  end

  def handle_event("close_meetings_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:viewing_contact, nil)
     |> assign(:viewing_meetings, [])}
  end

  # --- Private helpers ---

  defp load_contacts(socket) do
    user_id = socket.assigns.current_user.id
    search_term = socket.assigns[:search_term] || ""

    page =
      Contacts.list_contacts_page(
        user_id,
        search_term,
        socket.assigns.page,
        socket.assigns.per_page
      )

    assign(socket,
      contacts: page.entries,
      page: page.page,
      per_page: page.per_page,
      total: page.total,
      total_pages: page.total_pages
    )
  end

  defp atomize_contact_params(params) do
    Map.new(params, fn {field, value} -> {String.to_existing_atom(field), value} end)
  end

  defp get_contact_for_user(socket, id) do
    user_id = socket.assigns.current_user.id

    case Integer.parse(to_string(id)) do
      {contact_id, ""} -> Contacts.get_contact(contact_id, user_id)
      _other -> {:error, :not_found}
    end
  end

  defp open_form(socket, :create, nil) do
    socket
    |> assign(:show_form, true)
    |> assign(:form_mode, :create)
    |> assign(:contact_being_edited, nil)
    |> assign(:form_errors, %{})
    |> assign(:form_values, %{
      "name" => "",
      "email" => "",
      "phone" => "",
      "company" => "",
      "note" => ""
    })
  end

  defp open_form(socket, :edit, contact) do
    socket
    |> assign(:show_form, true)
    |> assign(:form_mode, :edit)
    |> assign(:contact_being_edited, contact)
    |> assign(:form_errors, %{})
    |> assign(:form_values, %{
      "name" => contact.name,
      "email" => contact.email,
      "phone" => contact.phone || "",
      "company" => contact.company || "",
      "note" => contact.note || ""
    })
  end

  defp close_form(socket) do
    socket
    |> assign(:show_form, false)
    |> assign(:form_mode, nil)
    |> assign(:contact_being_edited, nil)
    |> assign(:form_errors, %{})
    |> assign(:form_values, %{})
  end

  defp build_changeset(socket, form_values) do
    base =
      case socket.assigns.contact_being_edited do
        nil -> %ContactSchema{organizer_user_id: socket.assigns.current_user.id}
        contact -> contact
      end

    ContactSchema.changeset(base, form_values)
  end

  defp save_success_message(:create), do: dgettext("dashboard_contacts", "Contact added")
  defp save_success_message(:edit), do: dgettext("dashboard_contacts", "Contact updated")

  defp handle_feature_access_error(socket, :insufficient_plan) do
    Flash.error(dgettext("dashboard_contacts", "Contacts is available on Pro plans."))
    socket
  end

  defp handle_feature_access_error(socket, reason)
       when reason in [:pro_required, :feature_disabled] do
    Flash.error(dgettext("dashboard_contacts", "Contacts is available on the Pro plan."))
    socket
  end

  defp handle_feature_access_error(socket, _reason) do
    Flash.error(
      dgettext("dashboard_contacts", "Unable to perform this action. Please try again.")
    )

    socket
  end
end
