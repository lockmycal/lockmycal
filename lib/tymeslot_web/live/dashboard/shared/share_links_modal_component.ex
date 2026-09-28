defmodule TymeslotWeb.Dashboard.Shared.ShareLinksModalComponent do
  @moduledoc """
  The "Send by email" dialog for a host's public links (`Tymeslot.ShareLinks`):
  recipients, which links to include, and an optional personal message.

  Rendered once by `TymeslotWeb.DashboardLive`, outside every section, so the
  sidebar, the Overview page and the meeting types page can all open the same
  instance. Triggers target it by DOM id rather than going through the parent
  LiveView:

      phx-click="open" phx-target="#share-links-modal" phx-value-preselect="calendar"

  `preselect` is an optional link key (see `Tymeslot.ShareLinks`); the booking
  page is pre-selected when it is absent or unknown.
  """

  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Contacts
  alias Tymeslot.ShareLinks
  alias TymeslotWeb.Components.Dashboard.ContactPicker
  alias TymeslotWeb.Dashboard.Shared.ContactPickerHandlers

  @dom_id "share-links-modal"

  @doc "The DOM id triggers target with `phx-target`."
  @spec dom_id() :: String.t()
  def dom_id, do: @dom_id

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(:open, false)
     |> assign(:links, [])
     |> reset_form(["booking_page"])
     |> ContactPickerHandlers.reset()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("open", params, socket) do
    links = ShareLinks.links_for(socket.assigns.profile)
    preselect = Map.get(params, "preselect")
    keys = Enum.map(links, & &1.key)
    selected = if preselect in keys, do: [preselect], else: ["booking_page"]

    {:noreply,
     socket
     |> assign(:open, true)
     |> assign(:links, links)
     |> reset_form(selected)
     |> ContactPickerHandlers.reset()}
  end

  def handle_event("close", _params, socket) do
    {:noreply, assign(socket, :open, false)}
  end

  def handle_event("change", %{"share" => share}, socket) do
    {:noreply,
     socket
     |> assign(:recipients, Map.get(share, "recipients", ""))
     |> assign(:message, Map.get(share, "message", ""))
     |> assign(:selected, Map.get(share, "links", []))}
  end

  def handle_event("submit", %{"share" => share}, socket) do
    %{current_user: user, profile: profile, integration_status: status} = socket.assigns

    params = %{
      "recipients" => Map.get(share, "recipients", ""),
      "links" => Map.get(share, "links", []),
      "message" => Map.get(share, "message", "")
    }

    case ShareLinks.send_links(user, profile, status, params) do
      {:ok, count} ->
        Flash.info(
          dngettext(
            "dashboard_common",
            "Links sent to %{count} recipient.",
            "Links sent to %{count} recipients.",
            count
          )
        )

        {:noreply, assign(socket, :open, false)}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:recipients, params["recipients"])
         |> assign(:message, params["message"])
         |> assign(:selected, params["links"])
         |> assign(:errors, errors_for(reason))}
    end
  end

  def handle_event("query_contacts", params, socket),
    do: ContactPickerHandlers.query(params, socket, socket.assigns.current_user.id)

  def handle_event("close_contact_picker", _params, socket),
    do: ContactPickerHandlers.close(socket)

  def handle_event("select_contact", %{"id" => id}, socket) do
    with {contact_id, ""} <- Integer.parse(id),
         {:ok, contact} <- Contacts.get_contact(contact_id, socket.assigns.current_user.id) do
      {:noreply,
       socket
       |> assign(:recipients, append_recipient(socket.assigns.recipients, contact.email))
       |> ContactPickerHandlers.reset()}
    else
      _not_found -> {:noreply, ContactPickerHandlers.reset(socket)}
    end
  end

  defp reset_form(socket, selected) do
    socket
    |> assign(:recipients, "")
    |> assign(:message, "")
    |> assign(:selected, selected)
    |> assign(:errors, %{})
  end

  defp append_recipient(recipients, email) do
    case String.trim(recipients) do
      "" -> email
      current -> String.trim_trailing(current, ",") <> ", " <> email
    end
  end

  defp errors_for(:no_recipients),
    do: %{recipients: [dgettext("dashboard_common", "Enter at least one email address.")]}

  defp errors_for(:too_many_recipients),
    do: %{
      recipients: [
        dgettext("dashboard_common", "You can send to at most %{max} addresses at once.",
          max: ShareLinks.max_recipients()
        )
      ]
    }

  defp errors_for({:invalid_recipients, invalid}),
    do: %{
      recipients: [
        dgettext("dashboard_common", "Invalid email address: %{emails}",
          emails: Enum.join(invalid, ", ")
        )
      ]
    }

  defp errors_for(:no_links),
    do: %{links: [dgettext("dashboard_common", "Select at least one link to send.")]}

  defp errors_for(:message_too_long),
    do: %{
      message: [
        dgettext("dashboard_common", "The message can be at most %{max} characters long.",
          max: ShareLinks.max_message_length()
        )
      ]
    }

  defp errors_for(:rate_limited),
    do: %{
      general: [
        dgettext(
          "dashboard_common",
          "You have sent too many links recently. Please try again later."
        )
      ]
    }

  defp errors_for(:not_allowed),
    do: %{
      general: [
        dgettext("dashboard_common", "Complete setup to enable this feature")
      ]
    }

  defp link_dom_id(link), do: "share-links-link-" <> String.replace(link.key, ":", "-")

  defp link_label(%{kind: :booking_page}), do: dgettext("dashboard_common", "Booking page")
  defp link_label(%{kind: :calendar}), do: dgettext("dashboard_common", "Public calendar")

  defp link_label(%{kind: :meeting_type, name: name}),
    do: dgettext("dashboard_common", "Meeting type: %{name}", name: name)

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={dom_id()}>
      <.modal
        id={"#{dom_id()}-dialog"}
        show={@open}
        on_cancel={JS.push("close", target: @myself)}
        size={:medium}
      >
        <:header>
          {dgettext("dashboard_common", "Send links by email")}
        </:header>

        <div :if={@open} class="space-y-5">
          <.info_box :for={error <- Map.get(@errors, :general, [])} variant={:error}>
            {error}
          </.info_box>

          <div :if={@contacts_allowed}>
            <ContactPicker.contact_picker
              id="share-links-contact-picker"
              contacts={@contact_picker_results}
              query={@contact_picker_query}
              open={@contact_picker_open}
              target={@myself}
              query_event="query_contacts"
              select_event="select_contact"
              close_event="close_contact_picker"
            />
          </div>

          <form
            id="share-links-form"
            phx-change="change"
            phx-submit="submit"
            phx-target={@myself}
            class="space-y-5"
          >
            <.input
              id="share-links-recipients"
              name="share[recipients]"
              type="text"
              value={@recipients}
              label={dgettext("dashboard_common", "Recipients")}
              placeholder={dgettext("dashboard_common", "name@example.com, other@example.com")}
              icon="hero-envelope"
              required
              errors={Map.get(@errors, :recipients, [])}
            >
              <:description>
                {dgettext(
                  "dashboard_common",
                  "Separate multiple addresses with commas. Up to %{max} recipients.",
                  max: ShareLinks.max_recipients()
                )}
              </:description>
            </.input>

            <fieldset class="space-y-2">
              <legend class="block font-medium text-neutral-700 dark:text-neutral-200 mb-2">
                {dgettext("dashboard_common", "Links to include")}
              </legend>
              <%!-- `<.input>` always stacks its label above the control, so the
                   label text sits beside the checkbox in a wrapping <label>. --%>
              <label
                :for={link <- @links}
                for={link_dom_id(link)}
                class="flex items-center gap-3 cursor-pointer"
              >
                <.input
                  id={link_dom_id(link)}
                  name="share[links][]"
                  type="checkbox"
                  value={link.key}
                  checked={link.key in @selected}
                />
                <span class="text-token-sm text-neutral-700 dark:text-neutral-200">
                  {link_label(link)}
                </span>
              </label>
              <p
                :for={error <- Map.get(@errors, :links, [])}
                class="text-token-sm text-red-600 dark:text-red-400"
              >
                {error}
              </p>
            </fieldset>

            <.input
              id="share-links-message"
              name="share[message]"
              type="textarea"
              rows={3}
              value={@message}
              maxlength={ShareLinks.max_message_length()}
              label={dgettext("dashboard_common", "Personal message (optional)")}
              errors={Map.get(@errors, :message, [])}
            />
          </form>
        </div>

        <:footer>
          <div class="flex justify-end gap-3">
            <.action_button variant={:secondary} phx-click={JS.push("close", target: @myself)}>
              {dgettext("dashboard_common", "Cancel")}
            </.action_button>
            <.action_button type="submit" form="share-links-form" variant={:primary}>
              {dgettext("dashboard_common", "Send")}
            </.action_button>
          </div>
        </:footer>
      </.modal>
    </div>
    """
  end
end
