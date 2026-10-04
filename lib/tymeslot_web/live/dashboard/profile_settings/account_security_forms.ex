defmodule TymeslotWeb.Dashboard.ProfileSettings.AccountSecurityForms do
  @moduledoc """
  Form components for the email/password settings forms in the Profile page —
  shared by `EmailSettingsFormComponent` and `PasswordSettingsFormComponent`.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext
  alias Tymeslot.Validation.Constraints
  import TymeslotWeb.Components.CoreComponents

  @doc """
  Renders the email change form: new-email and current-password inputs next
  to the submit button on one row, matching `UsernameFormComponent`'s
  always-visible input+button layout rather than a hide/reveal toggle.
  """
  attr :errors, :map, required: true
  attr :saving, :boolean, required: true
  attr :myself, :any, required: true

  @spec email_form(map()) :: Phoenix.LiveView.Rendered.t()
  def email_form(assigns) do
    ~H"""
    <form
      id="account-email-form"
      phx-submit="update_email"
      phx-target={@myself}
      class="space-y-4"
      novalidate
    >
      <div class="flex flex-col sm:flex-row items-stretch gap-4">
        <div class="flex-1">
          <.input
            name="email_form[new_email]"
            autocomplete="email"
            type="email"
            label={dgettext("dashboard_profile", "New Email Address")}
            placeholder="your.new@email.com"
            errors={Map.get(@errors, :new_email) || []}
            required
            icon="hero-envelope"
          />
        </div>

        <div class="flex-1">
          <.input
            name="email_form[current_password]"
            autocomplete="current-password"
            type="password"
            label={dgettext("dashboard_profile", "Current Password")}
            placeholder={dgettext("dashboard_profile", "Enter your current password")}
            errors={Map.get(@errors, :current_password) || []}
            required
            icon="hero-lock-closed"
          />
        </div>

        <div class="flex items-end">
          <.loading_button
            type="submit"
            loading={@saving}
            loading_text={dgettext("dashboard_profile", "Updating...")}
            class="px-8 whitespace-nowrap h-[52px]"
          >
            {dgettext("dashboard_profile", "Update Email")}
          </.loading_button>
        </div>
      </div>

      <.form_errors errors={Map.get(@errors, :base)} />
    </form>
    """
  end

  @doc """
  Renders the password change form: the confirm-password input shares a row
  with the submit button, matching the email form's last-input+button layout.
  """
  attr :errors, :map, required: true
  attr :saving, :boolean, required: true
  attr :myself, :any, required: true

  @spec password_form(map()) :: Phoenix.LiveView.Rendered.t()
  def password_form(assigns) do
    ~H"""
    <form
      id="account-password-form"
      phx-submit="update_password"
      phx-target={@myself}
      class="space-y-4"
      novalidate
    >
      <.input
        name="password_form[current_password]"
        autocomplete="current-password"
        type="password"
        label={dgettext("dashboard_profile", "Current Password")}
        placeholder={dgettext("dashboard_profile", "Enter your current password")}
        errors={Map.get(@errors, :current_password) || []}
        required
        icon="hero-lock-closed"
      />

      <.input
        name="password_form[new_password]"
        autocomplete="new-password"
        type="password"
        label={dgettext("dashboard_profile", "New Password")}
        placeholder={dgettext("dashboard_profile", "At least 8 characters")}
        errors={Map.get(@errors, :new_password) || []}
        minlength={Constraints.password_length_range().first}
        required
        icon="hero-lock-closed"
      />

      <div class="flex flex-col sm:flex-row items-stretch gap-4">
        <div class="flex-1">
          <.input
            name="password_form[new_password_confirmation]"
            autocomplete="new-password"
            type="password"
            label={dgettext("dashboard_profile", "Confirm New Password")}
            placeholder={dgettext("dashboard_profile", "Confirm your new password")}
            errors={Map.get(@errors, :new_password_confirmation) || []}
            minlength={Constraints.password_length_range().first}
            required
            icon="hero-lock-closed"
          />
        </div>

        <div class="flex items-end">
          <.loading_button
            type="submit"
            loading={@saving}
            loading_text={dgettext("dashboard_profile", "Updating...")}
            class="px-8 whitespace-nowrap h-[52px]"
          >
            {dgettext("dashboard_profile", "Update Password")}
          </.loading_button>
        </div>
      </div>

      <.form_errors errors={Map.get(@errors, :base)} />
    </form>
    """
  end

  @doc """
  Renders form-level error messages.
  """
  attr :errors, :any, default: nil

  @spec form_errors(map()) :: Phoenix.LiveView.Rendered.t()
  def form_errors(assigns) do
    ~H"""
    <%= if @errors do %>
      <p class="text-sm text-red-400">{Enum.join(@errors, ", ")}</p>
    <% end %>
    """
  end
end
