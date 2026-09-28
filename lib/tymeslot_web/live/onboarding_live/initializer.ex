defmodule TymeslotWeb.OnboardingLive.Initializer do
  @moduledoc """
  Mount-time setup for the onboarding LiveView.

  Loads (or creates) the profile, seeds video backgrounds when a calendar is
  already connected, resolves the initial theme state, and assigns the full
  initial socket state including the avatar upload. Keeps the LiveView's
  `mount/3` a one-liner that delegates here.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1, allow_upload: 3]

  alias Phoenix.Component
  alias Tymeslot.Auth
  alias Tymeslot.Availability.Schedules
  alias Tymeslot.Features
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Onboarding
  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.Avatars
  alias Tymeslot.Timezones
  alias Tymeslot.Utils.UrlBuilder
  alias TymeslotWeb.CustomInputModeHelper
  alias TymeslotWeb.OnboardingLive.AvatarHandlers
  alias TymeslotWeb.OnboardingLive.BasicSettingsShared
  alias TymeslotWeb.OnboardingLive.StepConfig
  alias TymeslotWeb.OnboardingLive.ThemeHandlers
  alias TymeslotWeb.Themes.Core.ThemeInfo

  @doc """
  Builds the initial socket state for a freshly mounted onboarding session.
  """
  @spec initialize(Phoenix.LiveView.Socket.t(), map()) :: Phoenix.LiveView.Socket.t()
  def initialize(socket, user) do
    custom_username_allowed = custom_username_allowed?(user.id)
    profile = load_locked_profile(socket, user, custom_username_allowed)

    connected_calendars =
      if connected?(socket), do: Calendar.list_integrations(user.id), else: []

    # Seed both themes with a random video background the moment a calendar is
    # connected (the point the theme step unlocks), before reading the
    # customization below so the assigned state reflects it.
    ThemeHandlers.seed_video_backgrounds(profile, connected_calendars)

    {customization, color_scheme} = ThemeHandlers.initial_theme_state(profile)

    socket
    |> Component.assign(:profile, profile)
    |> Component.assign(:availability_schedule, load_default_schedule(profile))
    |> assign_form_data(profile)
    |> Component.assign(:current_step, :welcome)
    |> Component.assign(:step_data, %{})
    |> Component.assign(:show_skip_modal, false)
    |> Component.assign(:show_skip_calendar_modal, false)
    |> Component.assign(:show_theme_preview, false)
    |> Component.assign(:theme_preview_url, nil)
    |> Component.assign(:steps, StepConfig.steps(connected_calendars != []))
    |> Component.assign(:timezone_options, Timezones.all_options())
    |> Component.assign(:timezone_dropdown_open, false)
    |> Component.assign(:timezone_search, "")
    |> Component.assign(:page_title, dgettext("onboarding_wizard", "Welcome"))
    |> Component.assign(:form_errors, %{})
    |> Component.assign(:custom_input_mode, CustomInputModeHelper.default_custom_mode())
    |> Component.assign(:calendar_state, :selecting)
    |> Component.assign(:calendar_choice, nil)
    |> Component.assign(:connected_calendars, connected_calendars)
    |> Component.assign(:google_signup_email, Auth.google_signup_login_hint(user))
    |> Component.assign(:caldav_form_data, %{})
    |> Component.assign(:caldav_form_errors, %{})
    |> Component.assign(:caldav_discovering, false)
    |> Component.assign(:booking_url, build_booking_url(profile))
    |> Component.assign(:custom_username_allowed, custom_username_allowed)
    |> Component.assign(:theme_options, ThemeInfo.theme_options())
    |> Component.assign(:theme_customization, customization)
    |> Component.assign(:color_scheme, color_scheme)
    |> configure_avatar_upload()
  end

  defp configure_avatar_upload(socket) do
    allow_upload(socket, :avatar,
      accept: Avatars.accepted_extensions(),
      max_entries: 1,
      max_file_size: Avatars.max_file_size(),
      auto_upload: true,
      progress: &AvatarHandlers.handle_progress/3
    )
  end

  defp custom_username_allowed?(user_id),
    do: Features.check_access(user_id, :custom_username_allowed) == :ok

  defp load_locked_profile(socket, user, custom_username_allowed) do
    socket
    |> load_profile(user)
    |> ensure_locked_username(user.id, custom_username_allowed)
  end

  # When `:custom_username_allowed` is gated off (SaaS Free plan), the user never
  # gets to type a username, so it must exist up front instead of only being
  # backfilled at `complete_onboarding` time (`NavigationHandlers.ensure_username/2`) —
  # otherwise the profile step would have nothing to show in its read-only link.
  # Uses `Profiles.generate_locked_username/1` (cryptographically random, not
  # `user_<id>`) since this value is permanent for a locked user, unlike the
  # plain default `ensure_username/2` assigns an unlocked user who left the
  # field blank. `Profiles.assign_default_username/2` bypasses the
  # `:custom_username_allowed` gate itself (it's system-initiated).
  defp ensure_locked_username(nil, _user_id, _custom_username_allowed?), do: nil
  defp ensure_locked_username(profile, _user_id, true), do: profile

  defp ensure_locked_username(%{username: username} = profile, _user_id, false)
       when is_binary(username) and username != "",
       do: profile

  defp ensure_locked_username(profile, user_id, false) do
    locked_username = Profiles.generate_locked_username(user_id)

    case Profiles.assign_default_username(profile, locked_username) do
      {:ok, updated_profile} -> updated_profile
      {:error, _reason} -> profile
    end
  end

  defp assign_form_data(socket, nil), do: Component.assign(socket, :form_data, %{})

  defp assign_form_data(socket, _profile) do
    Component.assign(socket, :form_data, BasicSettingsShared.build_form_data(socket))
  end

  defp load_profile(socket, user) do
    if connected?(socket) do
      {:ok, loaded} = Onboarding.get_or_create_profile(user.id)
      {:ok, profile} = Profiles.ensure_timezone(loaded, get_connect_params(socket)["timezone"])
      profile
    else
      nil
    end
  end

  # The buffer, booking window and minimum notice edited by the preference
  # steps live on the profile's default availability schedule. There is no
  # profile during the disconnected render, so there is no schedule either.
  defp load_default_schedule(nil), do: nil
  defp load_default_schedule(profile), do: Schedules.get_default(profile.id)

  defp build_booking_url(nil), do: ""
  defp build_booking_url(profile), do: UrlBuilder.booking_url(profile.username)
end
