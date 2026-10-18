defmodule Tymeslot.Meetings.Ownership do
  @moduledoc """
  A user's side of a meeting — its organiser, or an attendee who booked it on
  someone else's page — and the one action only the organiser may take on it:
  deleting it. Called through `Tymeslot.Meetings`.
  """

  require Logger

  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Meetings.{BookerCalendarSync, MeetingQueries, MeetingSchema}

  @doc """
  Deletes a meeting for a specific user.
  Only the organizer can delete a meeting.
  Returns {:ok, meeting} if authorized and deleted, {:error, :unauthorized} if not authorized.
  """
  @spec delete_meeting_for_user(MeetingSchema.t(), String.t()) ::
          {:ok, MeetingSchema.t()} | {:error, :unauthorized | Ecto.Changeset.t()}
  def delete_meeting_for_user(%MeetingSchema{} = meeting, user_email)
      when is_binary(user_email) do
    if organized_by?(meeting, user_email) do
      remove_booker_copy(meeting)

      with {:ok, deleted} <- MeetingQueries.delete_meeting(meeting) do
        AttendeeAttachments.delete_batch(deleted.attendee_attachments)
        {:ok, deleted}
      end
    else
      {:error, :unauthorized}
    end
  end

  # The booker's own copy is optional, so one that cannot be removed does not
  # stop the deletion; it is only that nothing can take it away afterwards.
  defp remove_booker_copy(meeting) do
    case BookerCalendarSync.remove(meeting) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not remove the booker's calendar copy before deleting the meeting",
          meeting_id: meeting.id,
          reason: LogFormat.reason(reason)
        )
    end
  end

  @doc """
  Whether `user_email` is `meeting`'s organiser — the only one who may delete
  it with `delete_meeting_for_user/2`. The dashboard lists a user's meetings as
  organiser *and* as attendee, so a card uses this to offer organiser-only
  actions (Delete) and wording only where they apply.
  """
  @spec organized_by?(
          %{required(:organizer_email) => String.t() | nil, optional(atom()) => any()},
          String.t() | nil
        ) :: boolean()
  def organized_by?(%{organizer_email: organizer_email}, user_email),
    do: is_binary(user_email) and organizer_email == user_email

  @doc """
  Whether `user_email` attends `meeting` without organising it: a booking the
  user made on someone else's page, which their dashboard shows from their
  side (the host, the attendee's join link) and without the host's actions.
  """
  @spec attended_by?(
          %{
            required(:organizer_email) => String.t() | nil,
            required(:attendee_email) => String.t() | nil,
            optional(atom()) => any()
          },
          String.t() | nil
        ) :: boolean()
  def attended_by?(%{attendee_email: attendee_email} = meeting, user_email),
    do:
      is_binary(user_email) and attendee_email == user_email and
        not organized_by?(meeting, user_email)
end
