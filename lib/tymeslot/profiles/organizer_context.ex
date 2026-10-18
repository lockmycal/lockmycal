defmodule Tymeslot.Profiles.OrganizerContext do
  @moduledoc """
  Resolves organizer context for scheduling pages.

  Given a username (or the booking widget's alias, `Tymeslot.Profiles.EmbedAlias`),
  loads the organiser's profile, active meeting types, and assembles the context
  map consumed by scheduling LiveViews.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.MeetingTypes
  alias Tymeslot.Profiles.EmbedAlias

  @type username :: String.t()

  @doc """
  Resolves organiser context from a username, including profile and meeting types.

  An organiser whose account is scheduled for deletion resolves like one that
  does not exist: their meetings are being cancelled, and a booking taken now
  would be deleted with the account without its invitee ever being told.
  """
  @spec resolve_organizer_context(username()) :: {:ok, map()} | {:error, :profile_not_found}
  def resolve_organizer_context(username) when is_binary(username) do
    case EmbedAlias.get_by_handle_with_user(username) do
      {:ok, %{user: %{deletion_requested_at: %DateTime{}}}} ->
        {:error, :profile_not_found}

      {:ok, profile} ->
        meeting_types = load_active_meeting_types(profile.user_id)
        profile_with_meeting_types = %{profile | meeting_types: meeting_types}
        {:ok, build_organizer_context(profile_with_meeting_types, username)}

      {:error, :not_found} ->
        {:error, :profile_not_found}
    end
  end

  defp load_active_meeting_types(user_id) do
    MeetingTypes.get_public_meeting_types(user_id)
  end

  defp build_organizer_context(profile, username) do
    meeting_types = meeting_types_for_profile(profile)
    display_name = profile.full_name || get_user_name_from_profile(profile) || username

    %{
      username: username,
      # Reached through the booking widget's alias rather than the username:
      # the page then shows only what the widget may show.
      via_alias: EmbedAlias.alias?(username),
      profile: profile,
      user_id: profile.user_id,
      meeting_types: meeting_types,
      page_title: dgettext("booking", "Schedule with %{name}", name: display_name)
    }
  end

  defp get_user_name_from_profile(%{user: %{name: name}}), do: name
  defp get_user_name_from_profile(_arg), do: nil

  defp meeting_types_for_profile(%{meeting_types: meeting_types, user_id: user_id}) do
    if meeting_types != [] do
      meeting_types
    else
      if user_id, do: MeetingTypes.get_public_meeting_types(user_id), else: []
    end
  end
end
