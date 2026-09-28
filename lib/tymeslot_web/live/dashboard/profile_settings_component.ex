defmodule TymeslotWeb.Dashboard.ProfileSettingsComponent do
  @moduledoc """
  LiveView component for managing user profile settings including timezone,
  display name, scheduling preferences, and username configuration.

  This component acts as a container for specialized profile settings forms.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Components.Dashboard.Profile.DeleteAvatarModal

  alias TymeslotWeb.Dashboard.ProfileSettings.{
    AppearanceFormComponent,
    AvatarUploadComponent,
    CancelledMeetingsRetentionFormComponent,
    ContactDetailsFormComponent,
    ContactsSettingsFormComponent,
    DeleteAccountComponent,
    DisplayNameFormComponent,
    EmailSettingsFormComponent,
    LanguageFormComponent,
    PasswordSettingsFormComponent,
    TimeFormatFormComponent,
    TimezoneFormComponent,
    UsernameFormComponent
  }

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok, assign(socket, saving: false)}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div class="space-y-10 pb-20">
      <CoreComponents.section_header
        icon="hero-user"
        title={dgettext("dashboard_profile", "Profile Settings")}
        subtitle={
          dgettext(
            "dashboard_profile",
            "Manage your account, contact details, and scheduling preferences."
          )
        }
        saving={@saving}
      />

      <div class="card-glass relative overflow-hidden">
        <div class="relative z-10 grid grid-cols-1 lg:grid-cols-3 gap-12 items-start">
          <%!-- Avatar Section --%>
          <.live_component
            module={AvatarUploadComponent}
            id="avatar-upload"
            profile={@profile}
            current_user={@current_user}
          />

          <%!-- Settings Forms Section --%>
          <div class="lg:col-span-2 space-y-6 lg:border-l-2 lg:border-neutral-300 dark:lg:border-twilight-indigo-800 lg:pl-12 pt-4">
            <div class="space-y-6">
              <.live_component
                module={DisplayNameFormComponent}
                id="display-name-form"
                profile={@profile}
              />

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={ContactDetailsFormComponent}
                  id="contact-details-form"
                  profile={@profile}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={EmailSettingsFormComponent}
                  id="email-settings-form"
                  current_user={@current_user}
                  client_ip={@client_ip}
                  user_agent={@user_agent}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={PasswordSettingsFormComponent}
                  id="password-settings-form"
                  current_user={@current_user}
                  client_ip={@client_ip}
                  user_agent={@user_agent}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={LanguageFormComponent}
                  id="language-form"
                  current_user={@current_user}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={AppearanceFormComponent}
                  id="appearance-form"
                  current_user={@current_user}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={UsernameFormComponent}
                  id="username-form"
                  profile={@profile}
                  current_user={@current_user}
                  custom_username_allowed={@custom_username_allowed}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={TimezoneFormComponent}
                  id="timezone-form"
                  profile={@profile}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={TimeFormatFormComponent}
                  id="time-format-form"
                  current_user={@current_user}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={ContactsSettingsFormComponent}
                  id="contacts-settings-form"
                  profile={@profile}
                  contacts_allowed={@contacts_allowed}
                />
              </div>

              <div class="border-t-2 border-neutral-300 dark:border-twilight-indigo-800 pt-6">
                <.live_component
                  module={CancelledMeetingsRetentionFormComponent}
                  id="cancelled-meetings-retention-form"
                  profile={@profile}
                />
              </div>
            </div>
          </div>
        </div>
      </div>

      <.live_component
        module={DeleteAccountComponent}
        id="delete-account"
        current_user={@current_user}
        client_ip={@client_ip}
      />

      <%!-- Delete Avatar Modal (rendered outside card to avoid z-index stacking issues) --%>
      <.live_component
        module={DeleteAvatarModal}
        id="delete-avatar-modal"
        profile={@profile}
      />
    </div>
    """
  end
end
