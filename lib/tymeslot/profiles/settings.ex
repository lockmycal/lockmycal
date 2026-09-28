defmodule Tymeslot.Profiles.Settings do
  @moduledoc """
  Subcomponent for profile settings updates during onboarding and beyond.
  This module coordinates updates across multiple profile aspects.
  """

  alias Tymeslot.Availability.AvailabilityScheduleSchema
  alias Tymeslot.Availability.Schedules
  alias Tymeslot.Features
  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.ProfileSchema
  alias Tymeslot.Security.FieldValidators.UsernameValidator

  @policy_param_keys ~w(buffer_minutes advance_booking_days min_advance_hours)

  @type profile :: ProfileSchema.t()

  @typedoc ~S'String-keyed params from the basic-settings form (expects "full_name", "username", "timezone"; optionally "phone", "company").'
  @type basic_settings_params :: %{
          optional(String.t()) => term()
        }

  @typedoc ~S'String-keyed params from the scheduling-preferences form (expects "buffer_minutes", "advance_booking_days", "min_advance_hours").'
  @type scheduling_params :: %{
          optional(String.t()) => term()
        }

  @doc """
  Updates basic profile settings (name, username, timezone and the optional phone and
  company) with input validation.
  """
  @spec update_basic_settings(ProfileSchema.t(), %{String.t() => term()}) ::
          {:ok, ProfileSchema.t()} | {:error, term()}
  def update_basic_settings(profile, params) do
    # Extract the form fields, providing defaults if not present
    full_name = Map.get(params, "full_name", profile.full_name || "")
    username = clamp_username(profile, Map.get(params, "username", profile.username || ""))
    timezone = Map.get(params, "timezone", profile.timezone || "UTC")

    contact =
      for {key, field} <- [{"phone", :phone}, {"company", :company}],
          Map.has_key?(params, key),
          into: %{},
          do: {field, blank_to_nil(Map.get(params, key))}

    # Skip update if this is just a timezone search event (contains "value" key)
    if Map.has_key?(params, "value") do
      {:ok, profile}
    else
      # Validate username format if it changed
      with :ok <- validate_username_if_changed(profile, username) do
        perform_basic_update(profile, full_name, username, timezone, contact)
      end
    end
  end

  # Defense in depth: the onboarding profile step never renders a username
  # input when `:custom_username_allowed` is gated off (SaaS Free plan), but a
  # hand-crafted LiveView event could still submit a different value here —
  # silently keep the existing (system-assigned) username instead of failing
  # the whole basic-settings save, since name/timezone should still persist.
  defp clamp_username(profile, requested_username) do
    if requested_username != profile.username and
         Features.check_access(profile.user_id, :custom_username_allowed) != :ok do
      profile.username || ""
    else
      requested_username
    end
  end

  defp validate_username_if_changed(profile, new_username) do
    if profile.username != new_username do
      UsernameValidator.validate(new_username)
    else
      :ok
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: String.trim(value)
  end

  defp blank_to_nil(_value), do: nil

  defp perform_basic_update(profile, full_name, username, timezone, contact) do
    attrs =
      Map.merge(contact, %{
        full_name: full_name,
        username: username,
        timezone: timezone
      })

    Profiles.update_profile(profile, attrs)
  end

  @doc """
  Updates one scheduling preference on the profile's default availability
  schedule.

  Used by the onboarding wizard, which sets the account's starting policy before
  any additional schedule exists. The wizard submits one field at a time, so
  whichever of the three is present in `params` is the one that is written.
  """
  @spec update_scheduling_preferences(ProfileSchema.t(), %{String.t() => term()}) ::
          {:ok, AvailabilityScheduleSchema.t()} | {:error, term()}
  def update_scheduling_preferences(profile, params) do
    case {Map.take(params, @policy_param_keys), Schedules.get_default(profile.id)} do
      {_policy_params, nil} ->
        {:error, :no_default_schedule}

      {policy_params, schedule} when map_size(policy_params) == 0 ->
        {:ok, schedule}

      {policy_params, schedule} ->
        Schedules.update_policy(schedule, policy_params)
    end
  end

  @doc """
  Updates profile timezone.
  """
  @spec update_timezone(ProfileSchema.t(), String.t()) ::
          {:ok, ProfileSchema.t()} | {:error, term()}
  def update_timezone(profile, timezone) do
    Profiles.update_timezone(profile, timezone)
  end
end
