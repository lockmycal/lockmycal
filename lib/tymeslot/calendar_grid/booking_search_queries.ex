defmodule Tymeslot.CalendarGrid.BookingSearchQueries do
  @moduledoc """
  Query for the calendar grid's event search over the organiser's own
  bookings.

  The grid shows a booking that was never written back to a connected
  calendar as a projection of the booking itself
  (`Tymeslot.CalendarGrid.BookingEvents`), so a search of the cached provider
  events alone cannot find it. This finds those bookings by what the grid
  shows and what the booker told the organiser: the title, the meeting
  information, the description, the location and the booker's name and email.

  A booking that does have a cached provider copy is left out: the grid
  shows it through that copy, so the provider search is what finds it, and
  returning it here too would list it twice. "Has a copy" follows
  `Tymeslot.Meetings.CalendarEventLink`'s rule for the two families (Google
  and Outlook share the provider event id, the CalDAV family the event UID),
  and counts every cached row of the user's integrations, hidden calendars
  included, so a booking whose copy the user hid stays hidden.
  """

  import Ecto.Query

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema
  alias Tymeslot.Integrations.Calendar.ProviderCalendarEventSchema
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Meetings.MeetingState
  alias Tymeslot.Repo
  alias Tymeslot.Utils.LikeEscape

  @doc """
  The organiser's live bookings matching `term`, ordered by start time, at
  most `limit`. A blank term returns `[]`.
  """
  @spec search(pos_integer(), String.t(), pos_integer()) :: [MeetingSchema.t()]
  def search(organizer_user_id, term, limit) do
    case String.trim(to_string(term)) do
      "" ->
        []

      trimmed ->
        pattern = "%" <> LikeEscape.escape(trimmed) <> "%"

        MeetingSchema
        |> MeetingState.where_slot_live()
        |> from(as: :meeting)
        |> where([m], m.organizer_user_id == ^organizer_user_id)
        |> where(
          [m],
          ilike(m.title, ^pattern) or ilike(m.attendee_message, ^pattern) or
            ilike(m.description, ^pattern) or ilike(m.location, ^pattern) or
            ilike(m.attendee_name, ^pattern) or ilike(m.attendee_email, ^pattern)
        )
        |> where([m], not exists(synced_copy(organizer_user_id)))
        |> order_by([m], asc: m.start_time, asc: m.id)
        |> limit(^limit)
        |> Repo.all()
    end
  end

  defp synced_copy(user_id) do
    from(e in ProviderCalendarEventSchema,
      join: i in CalendarIntegrationSchema,
      on: i.id == e.calendar_integration_id,
      where: i.user_id == ^user_id,
      where:
        (not is_nil(parent_as(:meeting).provider_event_id) and
           parent_as(:meeting).provider_event_id != "" and
           e.provider_event_id == parent_as(:meeting).provider_event_id) or
          (not is_nil(parent_as(:meeting).calendar_uid) and
             parent_as(:meeting).calendar_uid != "" and
             e.uid == parent_as(:meeting).calendar_uid),
      select: 1
    )
  end
end
