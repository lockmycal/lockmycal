defmodule Tymeslot.Agenda do
  @moduledoc """
  Builds the dashboard agenda: a merged, deduplicated view of the user's
  upcoming Tymeslot bookings and synced external calendar events.

  The result (`Agenda.Day`) surfaces the next appointment as a hero and groups
  the rest into Today and Tomorrow, all in the user's timezone. This is a
  cross-domain read that orchestrates the `Meetings` and calendar contexts — it
  owns no storage of its own.
  """

  alias Tymeslot.Agenda.Day
  alias Tymeslot.Agenda.Entry
  alias Tymeslot.CalendarGrid
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.Appearance
  alias Tymeslot.Integrations.Calendar.EventColour
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.DisplayTitle
  alias Tymeslot.Meetings.MeetingState
  alias Tymeslot.Utils.DateTimeUtils

  # How far ahead to look for the hero when nothing is scheduled today/tomorrow.
  @lookahead_days 31
  @default_timezone "Etc/UTC"
  # Upper bound on bookings (confirmed or awaiting approval) pulled in — far
  # more than a two-day agenda plus a hero fallback ever needs.
  @meeting_limit 100

  # A booking's colour, as in the calendar grid.
  @booking_colour_class "bg-primary-600"
  # An unanswered request is always red: it is the one signal that the
  # organiser still owes the guest a decision.
  @awaiting_approval_colour_class "bg-red-600"
  # Upper bound on cached external calendar events pulled in for the lookahead
  # window — far more than a two-day agenda plus a hero fallback ever needs,
  # but wide enough to absorb a busy calendar's recurring-event instances.
  @external_event_limit 300

  @doc """
  Assembles the Today/Tomorrow agenda for `user` in `timezone`.

  `user` needs `:id` (to resolve calendar integrations) and `:email` (to resolve
  bookings). A nil/blank/unknown timezone falls back to UTC.
  """
  @spec day_agenda(map(), String.t() | nil) :: Day.t()
  def day_agenda(user, timezone) do
    now = DateTime.utc_now()
    tz = normalize_timezone(timezone)
    today = to_local_date(now, tz)
    tomorrow = Date.add(today, 1)
    window_end = DateTime.add(now, @lookahead_days * 86_400, :second)

    active = active_integrations(user)
    preferences = load_preferences(user)
    integrations = visible_integrations(active, preferences)
    title_source = preferences && preferences.booking_title_source
    appearances = load_appearances(user)
    hidden_calendar_keys = Appearance.hidden_keys(appearances)
    palette = palette(active, appearances)

    entries =
      user
      |> gather_entries(
        {integrations, hidden_calendar_keys, palette},
        {now, window_end, tz},
        title_source
      )
      |> Enum.filter(&upcoming?(&1, now))
      |> Enum.sort_by(& &1.start_at, DateTime)

    {next, rest} = pop_hero(entries)

    %Day{
      next: next,
      today: Enum.filter(rest, &Entry.covers?(&1, today, tz)),
      tomorrow: Enum.filter(rest, &Entry.covers?(&1, tomorrow, tz)),
      has_calendar?: integrations != [],
      later?: next != nil and Date.after?(next.day, tomorrow),
      timezone: tz
    }
  end

  # --- Gathering & merging ---------------------------------------------------

  defp gather_entries(
         user,
         {integrations, hidden_calendar_keys, palette},
         {now, window_end, tz},
         title_source
       ) do
    # Live confirmed bookings plus requests awaiting approval (shown marked as
    # such), excluding slots voided by a pending reschedule request; cancelled
    # and otherwise pending ones have no place on the agenda.
    meetings = Meetings.list_upcoming_agenda_meetings_for_user(user.email, @meeting_limit)

    # Bookings synced to the calendar reappear as provider events; dedup on the
    # shared identifier so the (richer) Tymeslot copy is the one we keep.
    booked_identifiers = Meetings.calendar_identifier_set(meetings)

    # Copies of bookings the agenda doesn't list (e.g. a cancelled one whose
    # provider copy has not synced away yet) must go too — matched by
    # identifier, since the stamp alone doesn't mean "a booking" (see
    # drop_external?/3).
    any_booking_identifiers =
      user.email
      |> Meetings.list_calendar_identities_for_organizer(now, window_end)
      |> Meetings.calendar_identifier_set()

    calendar_names = calendar_names(integrations)

    external =
      integrations
      |> Enum.map(& &1.id)
      |> CalendarGrid.list_events_for_range(now, window_end, limit: @external_event_limit)
      |> Calendar.visible_events(integrations)
      |> Enum.reject(
        &drop_external?(&1, {booked_identifiers, any_booking_identifiers}, hidden_calendar_keys)
      )

    Enum.map(meetings, &entry_from_meeting(&1, {tz, title_source, user.email}, calendar_names)) ++
      Enum.map(external, &entry_from_event(&1, tz, {calendar_names, palette}))
  end

  # An external event is dropped when it is one of our own synced bookings, a
  # cancellation, a free/transparent block, a timed event missing its start,
  # or the single calendar it sits in is hidden (the finer-grained sibling of
  # the whole-account `hidden_integration_ids` filter in `active_integrations/1`).
  #
  # `created_by_tymeslot` doesn't decide it either way: the CalDAV queue
  # (`QueueWiring`) stamps it on every write it queues, including an event the
  # organiser created or edited in the dashboard calendar, which is theirs to
  # see here; and a booking's copy synced back from Google or Outlook need not
  # carry it. So an event is dropped when it matches one of the organiser's
  # bookings in any status, whatever its stamp.
  defp drop_external?(event, {booked_identifiers, any_booking_identifiers}, hidden_calendar_keys) do
    Meetings.linked_to_calendar_event?(event, any_booking_identifiers) or
      event.status == "cancelled" or
      event.transparency == "transparent" or
      (not event.all_day and is_nil(event.start_at)) or
      Meetings.linked_to_calendar_event?(event, booked_identifiers) or
      MapSet.member?(
        hidden_calendar_keys,
        {event.calendar_integration_id, event.provider_calendar_id}
      )
  end

  # The hero is the next *timed* entry; all-day entries stay in their day group,
  # and so does a request awaiting approval — it is not an appointment yet.
  defp pop_hero(entries) do
    case Enum.find(entries, &(not &1.all_day? and not &1.awaiting_approval?)) do
      nil -> {nil, entries}
      hero -> {hero, List.delete(entries, hero)}
    end
  end

  defp upcoming?(%Entry{end_at: end_at}, now), do: DateTime.compare(end_at, now) == :gt

  # --- Normalisation ---------------------------------------------------------

  defp entry_from_meeting(meeting, {tz, title_source, user_email}, calendar_names) do
    awaiting_approval? = MeetingState.awaiting_approval?(meeting)
    attending? = not Meetings.organized_by?(meeting, user_email)

    %Entry{
      id: "meeting-" <> to_string(meeting.id),
      source: :tymeslot,
      title: meeting_title(meeting, title_source, attending?),
      day: to_local_date(meeting.start_time, tz),
      start_at: meeting.start_time,
      end_at: meeting.end_time,
      all_day?: false,
      location: presence(meeting.location),
      join_url: join_url(meeting, attending?),
      who: presence(if attending?, do: meeting.organizer_name, else: meeting.attendee_name),
      calendar:
        calendar_name(meeting.calendar_integration_id, meeting.calendar_path, calendar_names),
      colour: nil,
      colour_class: meeting_colour_class(awaiting_approval?),
      source_id: meeting.id,
      awaiting_approval?: awaiting_approval?,
      attending?: attending?
    }
  end

  # One the user made elsewhere is titled from their side, after whom it is
  # with, under the same preference of theirs.
  defp meeting_title(meeting, title_source, true = _attending?),
    do: DisplayTitle.attendee_title(meeting, title_source)

  defp meeting_title(meeting, title_source, false = _attending?),
    do: DisplayTitle.title(meeting, title_source)

  defp join_url(meeting, true = _attending?),
    do: presence(meeting.attendee_video_url) || presence(meeting.meeting_url)

  defp join_url(meeting, false = _attending?),
    do: presence(meeting.organizer_video_url) || presence(meeting.meeting_url)

  defp entry_from_event(%{all_day: true} = event, tz, {calendar_names, palette}) do
    end_date = event.end_date || Date.add(event.start_date, 1)

    %Entry{
      id: "event-" <> to_string(event.id),
      source: :external,
      title: presence(event.summary) || "Busy",
      day: event.start_date,
      start_at: local_midnight(event.start_date, tz),
      end_at: local_midnight(end_date, tz),
      all_day?: true,
      location: presence(event.location),
      join_url: nil,
      who: organiser_name(event.organiser),
      calendar: calendar_name(event, calendar_names),
      colour: event.colour,
      colour_class: event_colour_class(event, palette),
      source_id: event.id
    }
  end

  defp entry_from_event(event, tz, {calendar_names, palette}) do
    end_at = event.end_at || DateTime.add(event.start_at, 3600, :second)

    %Entry{
      id: "event-" <> to_string(event.id),
      source: :external,
      title: presence(event.summary) || "Busy",
      day: to_local_date(event.start_at, tz),
      start_at: event.start_at,
      end_at: end_at,
      all_day?: false,
      location: presence(event.location),
      join_url: presence(event.video_link),
      who: organiser_name(event.organiser),
      calendar: calendar_name(event, calendar_names),
      colour: event.colour,
      colour_class: event_colour_class(event, palette),
      source_id: event.id
    }
  end

  defp meeting_colour_class(true = _awaiting_approval?), do: @awaiting_approval_colour_class
  defp meeting_colour_class(false = _awaiting_approval?), do: @booking_colour_class

  # Same precedence as the calendar grid (`EventPositioning.color_for_event/2`):
  # the event's own (provider) colour, then the colour
  # chosen for its calendar, then its integration's colour or rotation slot.
  defp event_colour_class(event, palette) do
    EventColour.tailwind_class(event.colour) ||
      Map.get(palette.calendars, {event.calendar_integration_id, event.provider_calendar_id}) ||
      Map.get(palette.integrations, event.calendar_integration_id, EventColour.fallback_class())
  end

  # --- Helpers ---------------------------------------------------------------

  defp active_integrations(%{id: id}) when is_integer(id) do
    id
    |> Calendar.list_integrations()
    |> Enum.filter(& &1.is_active)
  end

  defp active_integrations(_user), do: []

  defp load_preferences(%{id: id}) when is_integer(id),
    do: CalendarGrid.get_or_create_preferences(id)

  defp load_preferences(_user), do: nil

  defp visible_integrations(_active, nil), do: []

  defp visible_integrations(active, preferences),
    do: Enum.reject(active, &(&1.id in preferences.hidden_integration_ids))

  # The calendar grid's colours, so an appointment wears the same colour here
  # as in the calendar: per-calendar choices, then each integration's colour —
  # the rotation computed over every active integration, hidden ones included,
  # exactly as the grid does, or the rotated colours would shift.
  defp palette(active, appearances) do
    %{
      calendars: CalendarGrid.calendar_colour_classes(appearances),
      integrations: CalendarGrid.integration_colour_classes(active)
    }
  end

  # Both the hidden calendars and their colours come from these rows; with no
  # user they're simply none, which `Appearance.hidden_keys/1` turns into the
  # same MapSet construction as the non-empty case (see Dialyzer's opaque
  # MapSet shapes).
  defp load_appearances(%{id: id}) when is_integer(id), do: Appearance.list_for_user(id)
  defp load_appearances(_user), do: []

  # Display names keyed by `{integration_id, calendar}`: each calendar in an
  # integration's `calendar_list` under both its `id` and `path` (what a
  # provider event's `provider_calendar_id` / a meeting's `calendar_path` hold,
  # depending on the provider), plus `{integration_id, nil}` for the
  # integration's own name — the fallback when the calendar isn't listed.
  #
  # An integration with a single calendar in use is named after itself
  # ("Itopo"); one with several is qualified by the calendar
  # ("Pavliks.eu - Tymeslot"), since the account name alone no longer says
  # which of them an entry sits in.
  defp calendar_names(integrations) do
    Enum.reduce(integrations, %{}, fn integration, acc ->
      calendars = integration.calendar_list || []
      several? = in_use_count(calendars) > 1
      acc = Map.put(acc, {integration.id, nil}, integration.name)

      Enum.reduce(calendars, acc, fn calendar, acc ->
        label = calendar_label(integration.name, calendar.name, several?)

        [calendar.id, calendar.path]
        |> Enum.reject(&is_nil/1)
        |> Enum.reduce(acc, &Map.put(&2, {integration.id, &1}, label))
      end)
    end)
  end

  # Calendars the user syncs; a list without any selection flag set (providers
  # that predate the flag) counts all of its calendars.
  defp in_use_count(calendars) do
    case Enum.count(calendars, & &1.selected) do
      0 -> length(calendars)
      selected -> selected
    end
  end

  defp calendar_label(integration_name, calendar_name, true = _several?) do
    case {presence(integration_name), presence(calendar_name)} do
      {nil, calendar} -> calendar
      {integration, nil} -> integration
      {integration, calendar} -> "#{integration} - #{calendar}"
    end
  end

  defp calendar_label(integration_name, _calendar_name, false = _several?),
    do: integration_name

  defp calendar_name(%{calendar_integration_id: id, provider_calendar_id: calendar}, names),
    do: calendar_name(id, calendar, names)

  defp calendar_name(nil, _calendar, _names), do: nil

  defp calendar_name(integration_id, calendar, names) do
    presence(Map.get(names, {integration_id, calendar})) ||
      presence(Map.get(names, {integration_id, nil}))
  end

  defp to_local_date(datetime, tz) do
    datetime
    |> DateTimeUtils.convert_to_timezone(tz)
    |> DateTime.to_date()
  end

  # Total by construction: midnight can be a DST gap or ambiguous in some zones,
  # and an all-day chip must never crash the dashboard.
  defp local_midnight(date, tz), do: DateTimeUtils.create_datetime_safe(date, ~T[00:00:00], tz)

  defp organiser_name(organiser) when is_map(organiser) do
    presence(organiser["displayName"]) || presence(organiser["name"]) ||
      presence(organiser["email"]) || presence(organiser[:displayName]) ||
      presence(organiser[:name]) || presence(organiser[:email])
  end

  defp organiser_name(_organiser), do: nil

  defp normalize_timezone(tz) when is_binary(tz) and tz != "" do
    case DateTime.now(tz) do
      {:ok, _dt} -> tz
      _error -> @default_timezone
    end
  end

  defp normalize_timezone(_tz), do: @default_timezone

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil
end
