defmodule Tymeslot.MeetingTypes.Visibility do
  @moduledoc """
  Where a meeting type is listed: the public booking page and the embedded
  booking widget, each controlled by its own flag.

    * `is_private` hides the type from the public booking page.
    * `show_in_embed` lists the type in the embedded widget's overview.

  The two are independent, so a type can be listed in the widget only, on the
  public page only, in both or in neither. Neither flag affects the direct
  link (`/:username/:slug`): an active type stays bookable through it.
  """

  alias Tymeslot.MeetingTypes.GroupAccess
  alias Tymeslot.MeetingTypes.MeetingTypeQueries

  @doc """
  Gets the meeting types listed in the organiser's embedded booking widget
  (active and `show_in_embed`). The widget's counterpart of
  `Tymeslot.MeetingTypes.get_public_meeting_types/1`, read the same way: no
  seeding, and a paused group type is left out.
  """
  @spec get_embed_meeting_types(integer()) :: [Ecto.Schema.t()]
  def get_embed_meeting_types(user_id) do
    user_id
    |> MeetingTypeQueries.list_embed_meeting_types()
    |> GroupAccess.reject_paused()
  end

  @doc """
  Gets the meeting types bookable through their direct link (active, a paused
  group type left out): the set `Tymeslot.MeetingTypes.find_by_slug/2`
  resolves, whatever the two listing flags say. Offered as the choices for a
  widget pinned to one meeting type.
  """
  @spec get_linkable_meeting_types(integer()) :: [Ecto.Schema.t()]
  def get_linkable_meeting_types(user_id) do
    user_id
    |> MeetingTypeQueries.list_active_meeting_types()
    |> GroupAccess.reject_paused()
  end

  @doc """
  Whether a meeting type may be booked through the organiser's widget alias
  (`Tymeslot.Profiles.EmbedAlias`): one that is private or shown in the
  widget. A type that is only on the public page stays out of reach, or the
  alias would hide nothing.
  """
  @spec reachable_via_alias?(map()) :: boolean()
  def reachable_via_alias?(meeting_type),
    do:
      Map.get(meeting_type, :is_private) == true or Map.get(meeting_type, :show_in_embed) == true

  @doc """
  Sets whether a meeting type is private. A private type is excluded from the
  organiser's public booking page but stays reachable by its direct link.
  """
  @spec set_private(Ecto.Schema.t(), boolean()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def set_private(meeting_type, is_private) when is_boolean(is_private) do
    MeetingTypeQueries.set_visibility(meeting_type, %{is_private: is_private})
  end

  @doc """
  Sets whether a meeting type is listed in the organiser's embedded booking
  widget.
  """
  @spec set_show_in_embed(Ecto.Schema.t(), boolean()) ::
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def set_show_in_embed(meeting_type, show_in_embed) when is_boolean(show_in_embed) do
    MeetingTypeQueries.set_visibility(meeting_type, %{show_in_embed: show_in_embed})
  end
end
