defmodule TymeslotWeb.Dashboard.Contacts.FormComponent do
  @moduledoc """
  Full-page create/edit form for a contact, swapped in by
  `TymeslotWeb.Dashboard.Contacts.HubComponent` in place of the list —
  same layout as `TymeslotWeb.Dashboard.Automation.WebhookFormComponent`.

  Stateless with respect to persistence: every event (`validate_field`,
  `save_contact`, `close_form`) is pushed to `@parent_component`, which owns
  `form_values`/`form_errors` and talks to `Tymeslot.Contacts`.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Live.Shared.FormValidationHelpers

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, :can_submit, can_submit?(assigns))

    ~H"""
    <div class="space-y-8 pb-20">
      <div class="flex flex-col md:flex-row md:items-start md:justify-between gap-6 mb-0">
        <div>
          <.section_header
            icon="hero-identification"
            title={
              if @mode == :create,
                do: dgettext("dashboard_contacts", "Add Contact"),
                else: dgettext("dashboard_contacts", "Edit Contact")
            }
            subtitle={dgettext("dashboard_contacts", "Keep track of the people who book with you.")}
          />
        </div>

        <button
          phx-click="close_form"
          phx-target={@parent_component}
          class="modal-icon-button"
          aria-label={dgettext("dashboard_contacts", "Close")}
          title={dgettext("dashboard_contacts", "Close")}
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2.5"
              d="M6 18L18 6M6 6l12 12"
            />
          </svg>
        </button>
      </div>

      <form
        id="contact-form"
        phx-submit={JS.push("save_contact", target: @parent_component)}
        phx-target={@parent_component}
        class="space-y-8"
      >
        <div>
          <.subsection_header
            icon="hero-identification"
            title={dgettext("dashboard_contacts", "Contact Details")}
            class="mb-2"
          />

          <div class="card-glass space-y-6">
            <.input
              name="contact[name]"
              label={dgettext("dashboard_contacts", "Name")}
              value={Map.get(@form_values, "name", "")}
              phx-blur={
                JS.push("validate_field", value: %{"field" => "name"}, target: @parent_component)
              }
              required
              errors={FormValidationHelpers.field_errors(@form_errors, :name)}
              icon="hero-user"
            />

            <.input
              name="contact[email]"
              type="email"
              label={dgettext("dashboard_contacts", "Email")}
              value={Map.get(@form_values, "email", "")}
              phx-blur={
                JS.push("validate_field", value: %{"field" => "email"}, target: @parent_component)
              }
              required
              errors={FormValidationHelpers.field_errors(@form_errors, :email)}
              icon="hero-envelope"
            />

            <.input
              name="contact[phone]"
              type="tel"
              label={dgettext("dashboard_contacts", "Phone")}
              value={Map.get(@form_values, "phone", "")}
              phx-blur={
                JS.push("validate_field", value: %{"field" => "phone"}, target: @parent_component)
              }
              errors={FormValidationHelpers.field_errors(@form_errors, :phone)}
              icon="hero-phone"
            />

            <.input
              name="contact[company]"
              label={dgettext("dashboard_contacts", "Company")}
              value={Map.get(@form_values, "company", "")}
              phx-blur={
                JS.push("validate_field", value: %{"field" => "company"}, target: @parent_component)
              }
              errors={FormValidationHelpers.field_errors(@form_errors, :company)}
              icon="hero-building-office"
            />
          </div>
        </div>

        <div>
          <.subsection_header
            icon="hero-pencil-square"
            title={dgettext("dashboard_contacts", "Note")}
            class="mb-2"
          />

          <div class="card-glass">
            <p class="text-token-sm text-neutral-500 font-bold mb-4">
              {dgettext(
                "dashboard_contacts",
                "Private to you — visible only on this contact's row and form."
              )}
            </p>

            <.input
              type="textarea"
              name="contact[note]"
              value={Map.get(@form_values, "note", "")}
              phx-blur={
                JS.push("validate_field", value: %{"field" => "note"}, target: @parent_component)
              }
              errors={FormValidationHelpers.field_errors(@form_errors, :note)}
              rows={4}
            />
          </div>
        </div>

        <div class="flex justify-end gap-3 pt-4">
          <CoreComponents.action_button
            variant={:secondary}
            phx-click="close_form"
            phx-target={@parent_component}
          >
            {dgettext("dashboard_contacts", "Cancel")}
          </CoreComponents.action_button>
          <CoreComponents.loading_button
            type="submit"
            variant={:primary}
            loading={@saving}
            loading_text={dgettext("dashboard_contacts", "Saving...")}
            disabled={!@can_submit}
            class={if !@can_submit, do: "opacity-50 cursor-not-allowed grayscale", else: ""}
          >
            {if @mode == :create,
              do: dgettext("dashboard_contacts", "Add Contact"),
              else: dgettext("dashboard_contacts", "Update Contact")}
          </CoreComponents.loading_button>
        </div>
      </form>
    </div>
    """
  end

  defp can_submit?(assigns) do
    values = assigns.form_values
    errors = assigns.form_errors

    field_present?(values, "name") && field_present?(values, "email") && Enum.empty?(errors)
  end

  defp field_present?(values, key), do: String.trim(Map.get(values, key, "")) != ""
end
