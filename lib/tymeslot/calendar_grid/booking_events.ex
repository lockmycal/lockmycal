defmodule Tymeslot.CalendarGrid.BookingEvents do
  @moduledoc """
  Loads the organiser's bookings for a grid window as `BookingEvent` structs.

  This is the calendar grid's native view of Tymeslot bookings: it reads
  through the `Meetings` context and projects each live booking into the
  grid's event shape. Deduplication against provider-synced copies of the
  same bookings happens here so callers get a list that can be concatenated
  onto the cached provider events directly.
  """

  alias Tymeslot.CalendarGrid.BookingEvent
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.DisplayTitle
  alias Tymeslot.Meetings.MeetingState

  @doc """
  Returns the user's live bookings overlapping `[start_dt, end_dt)` as
  `BookingEvent` structs, excluding any whose synced provider copy is already
  present.

  `cached_events` is the cached provider events loaded for the same window. A
  booking that has been written back to a connected calendar reappears in the
  cache as a `created_by_tymeslot` event; that copy stays the interactive one
  on the grid, so the booking projection is dropped to avoid a duplicate
  block.

  The exception is a booking awaiting approval. Its synced copy is the
  tentative hold the booking wrote to keep the slot, which carries none of the
  booking's state and would paint as an ordinary event. Such a booking is kept,
  stamped with its hold's `calendar_integration_id`/`provider_calendar_id` so
  the grid's calendar visibility filters treat it like the hold, and the caller
  shows it in place of the hold (see `stands_in_for_hold?/1`).

  Pass the cached events themselves rather than a pre-extracted key set: which
  identifier links the two sides varies by provider family, and
  `Tymeslot.Meetings.CalendarEventLink` is the one place that knows the rule.

  `title_source` picks each projection's `summary` (see
  `Tymeslot.Meetings.DisplayTitle`); it defaults to the booking's own title.
  """
  @spec list_for_range(
          pos_integer(),
          DateTime.t(),
          DateTime.t(),
          Enumerable.t(),
          String.t()
        ) :: [BookingEvent.t()]
  def list_for_range(
        user_id,
        start_dt,
        end_dt,
        cached_events \\ [],
        title_source \\ "meeting_type"
      ) do
    {booking_events, _cached_events} =
      load_for_range(user_id, {start_dt, end_dt}, cached_events, title_source)

    booking_events
  end

  @doc """
  `list_for_range/5` plus `cached_events` with every synced copy of a booking
  annotated from that booking: renamed to its display title under
  `title_source`, and carrying its `attendee_attachments` when it has any.

  A synced booking is shown on the grid through its provider copy, whose
  summary is whatever was written to the calendar (the meeting-type-based
  title) and which knows nothing of the booker's files. Annotating it here
  keeps a booking titled and marked the same way whether or not it has
  synced — from one load of the window's bookings.
  """
  @spec load_for_range(
          pos_integer(),
          {DateTime.t(), DateTime.t()},
          Enumerable.t(),
          String.t() | nil
        ) :: {[BookingEvent.t()], [map()]}
  def load_for_range(user_id, {start_dt, end_dt}, cached_events, title_source) do
    synced_identifiers = Meetings.calendar_identifier_set(cached_events)
    meetings = Meetings.list_meetings_in_range_for_organizer(user_id, start_dt, end_dt)

    booking_events =
      Enum.flat_map(meetings, fn meeting ->
        cond do
          not Meetings.linked_to_calendar_event?(meeting, synced_identifiers) ->
            [to_event(meeting, title_source)]

          MeetingState.awaiting_approval?(meeting) ->
            [in_place_of_hold(to_event(meeting, title_source), meeting, cached_events)]

          true ->
            []
        end
      end)

    {booking_events, annotate_synced(cached_events, meetings, title_source)}
  end

  # Keyed by every identifier a booking carries, so each cached event is
  # matched with a map lookup rather than a scan over the bookings. Only
  # bookings with something to annotate are indexed: under "meeting_type"
  # the provider copy already carries the booking's own title — or whatever
  # the organiser renamed it to in their calendar, which must win.
  defp annotate_synced(cached_events, meetings, title_source) do
    by_identifier =
      for meeting <- meetings,
          title_source != "meeting_type" or meeting.attendee_attachments not in [nil, []],
          identifier <- Meetings.calendar_event_identifiers(meeting),
          into: %{},
          do: {identifier, meeting}

    if by_identifier == %{} do
      Enum.to_list(cached_events)
    else
      Enum.map(cached_events, &annotate_event(&1, by_identifier, title_source))
    end
  end

  defp annotate_event(event, by_identifier, title_source) do
    identifiers = Meetings.calendar_event_identifiers(event)

    case Enum.find_value(identifiers, &Map.get(by_identifier, &1)) do
      nil -> event
      meeting -> event |> retitle(meeting, title_source) |> put_attachments(meeting)
    end
  end

  defp retitle(event, _meeting, "meeting_type"), do: event

  defp retitle(event, meeting, title_source),
    do: Map.put(event, :summary, DisplayTitle.title(meeting, title_source))

  # The booking's id travels along so the event's detail dialog can link each
  # file to its dashboard download.
  defp put_attachments(event, %{id: meeting_id, attendee_attachments: [_first | _rest] = files}) do
    event
    |> Map.put(:attendee_attachments, files)
    |> Map.put(:booking_meeting_id, meeting_id)
  end

  defp put_attachments(event, _meeting), do: event

  @doc """
  Whether `booking_event` is a booking awaiting approval shown in place of its
  synced tentative hold (see `list_for_range/4`), so the caller must leave that
  hold out of the grid.
  """
  @spec stands_in_for_hold?(BookingEvent.t()) :: boolean()
  def stands_in_for_hold?(%BookingEvent{status: status, calendar_integration_id: id}),
    do: status == "awaiting_approval" and not is_nil(id)

  defp in_place_of_hold(event, meeting, cached_events) do
    identifiers = Meetings.calendar_identifier_set([meeting])
    hold = Enum.find(cached_events, &Meetings.linked_to_calendar_event?(&1, identifiers))

    %{
      event
      | calendar_integration_id: hold.calendar_integration_id,
        provider_calendar_id: Map.get(hold, :provider_calendar_id)
    }
  end

  defp to_event(meeting, title_source) do
    %BookingEvent{
      id: "booking-#{meeting.id}",
      meeting_id: meeting.id,
      # The event-shaped identity, matching the provider copy's `uid`.
      uid: meeting.calendar_uid,
      summary: DisplayTitle.title(meeting, title_source),
      location: presence(meeting.location),
      description: presence(meeting.description),
      attendee_message: presence(meeting.attendee_message),
      attendee_attachments: meeting.attendee_attachments || [],
      start_at: meeting.start_time,
      end_at: meeting.end_time,
      attendee_name: presence(meeting.attendee_name),
      attendee_email: presence(meeting.attendee_email),
      join_url: presence(meeting.organizer_video_url) || presence(meeting.meeting_url),
      provider_event_id: meeting.provider_event_id,
      status: meeting.status
    }
  end

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil
end
