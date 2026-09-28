defmodule TymeslotWeb.Dashboard.ProfileSettings.ContactDetailsFormComponent do
  @moduledoc """
  Optional phone and company form for profile settings. The values pre-fill the
  booking form when the user books a meeting with someone else.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Profiles
  alias Tymeslot.Security.InputProcessor
  alias TymeslotWeb.Live.Shared.FormValidationHelpers
  import TymeslotWeb.Components.CoreComponents

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, :form_errors, %{})}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("validate_contact_details", params, socket) do
    phone = Map.get(params, "phone", "")
    company = Map.get(params, "company", "")

    with {:ok, phone} <- validate(phone, :phone, :phone),
         {:ok, company} <- validate(company, :name, :company) do
      socket = assign(socket, :form_errors, %{})
      maybe_update(socket, %{phone: blank_to_nil(phone), company: blank_to_nil(company)})
    else
      {:error, field, message} ->
        {:noreply, assign(socket, :form_errors, %{field => message})}
    end
  end

  defp validate(value, type, field) do
    case InputProcessor.validate_field(value, type, required: false) do
      {:ok, sanitized} -> {:ok, sanitized}
      {:error, message} -> {:error, field, message}
    end
  end

  defp blank_to_nil(value) do
    if String.trim(value) == "", do: nil, else: String.trim(value)
  end

  defp maybe_update(socket, attrs) do
    profile = socket.assigns.profile

    if profile && attrs != %{phone: profile.phone, company: profile.company} do
      case Profiles.update_contact_details(profile, attrs) do
        {:ok, updated_profile} ->
          send(self(), {:profile_updated, updated_profile})
          Flash.info(dgettext("dashboard_profile", "Contact details updated"))
          {:noreply, assign(socket, profile: updated_profile)}

        {:error, _reason} ->
          Flash.error(dgettext("dashboard_profile", "Failed to update contact details"))
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="contact-details-form-container">
      <.subsection_header
        icon="hero-phone"
        title={dgettext("dashboard_profile", "Contact Details")}
        class="mb-3"
      />
      <.form_wrapper
        for={%{}}
        phx-change="validate_contact_details"
        phx-target={@myself}
        id="contact-details-form"
      >
        <div class="space-y-4">
          <.input
            name="phone"
            autocomplete="tel"
            type="tel"
            label={dgettext("dashboard_profile", "Phone")}
            value={if @profile, do: @profile.phone || "", else: ""}
            placeholder={dgettext("dashboard_profile", "+420 123 456 789")}
            errors={FormValidationHelpers.field_errors(@form_errors, :phone)}
            phx-debounce="blur"
          />
          <.input
            name="company"
            autocomplete="organization"
            label={dgettext("dashboard_profile", "Company")}
            value={if @profile, do: @profile.company || "", else: ""}
            placeholder={dgettext("dashboard_profile", "Acme Inc.")}
            errors={FormValidationHelpers.field_errors(@form_errors, :company)}
            phx-debounce="blur"
          />
        </div>
      </.form_wrapper>
      <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
        {dgettext(
          "dashboard_profile",
          "Used to pre-fill the booking form when you book a meeting with someone else. Changes are saved automatically."
        )}
      </p>
    </div>
    """
  end
end
