defmodule Tymeslot.Meetings.BookerCalendarSync do
  @moduledoc """
  Writes, moves and removes the booker's own copy of a meeting
  (`Tymeslot.Meetings.BookerCalendar`), run by
  `Tymeslot.Workers.BookerCalendarEventWorker`.

  One entry point, `sync/1`, decides from the meeting as it now stands rather
  than from the action that prompted it: a meeting that expects a calendar
  event gets its copy written or updated, one that no longer does has it
  removed. A sync that runs late, or twice, therefore still converges on the
  right state.

  The copy is the booker's plain personal entry, not an invitation. It names
  no attendees: a provider that invites everyone on an event (Microsoft Graph
  does) would otherwise send the organiser an invitation from the booker's
  account. It is written under a UID of its own (`copy_uid/1`), so neither the
  booker's calendar sync nor the organiser's can mistake it for the
  organiser's event, and a retried create addresses the same event.

  A booker whose calendar can no longer take the copy simply has none:
  nothing here alerts them, since the confirmation email's `.ics` already
  gives every booker a way to add the meeting themselves.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Auth
  alias Tymeslot.CalendarGrid
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Integrations.Calendar.CreatedEvent
  alias Tymeslot.Integrations.CalendarManagement
  alias Tymeslot.Locales
  alias Tymeslot.Meetings.BookerCalendar
  alias Tymeslot.Meetings.DisplayTitle
  alias Tymeslot.Meetings.MeetingQueries
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Meetings.MeetingState

  require Logger

  @doc """
  Brings the booker's copy of `meeting_id` in step with the meeting.

  `:ok` when nothing is left to do, including a meeting that is gone or has
  no booker who asked for a copy; `{:error, reason}` for a write the worker
  should retry or give up on.
  """
  @spec sync(String.t()) :: :ok | {:error, term()}
  def sync(meeting_id) do
    case MeetingQueries.get_meeting(meeting_id) do
      {:ok, meeting} -> sync_meeting(meeting)
      {:error, :not_found} -> :ok
    end
  end

  defp sync_meeting(meeting) do
    cond do
      wants_copy?(meeting) and mapped?(meeting) -> update_copy(meeting)
      wants_copy?(meeting) -> create_copy(meeting)
      mapped?(meeting) -> remove_copy(meeting)
      true -> :nothing_written
    end
    |> refresh_booker_calendar(meeting.booker_user_id)
  end

  # The booker's calendar grid shows the copy from the cache their own
  # calendar's sync fills, so it would only appear (move, disappear) a sync
  # cycle later. A sync of that calendar is asked for right away instead.
  defp refresh_booker_calendar({:written, integration_id}, user_id) do
    case CalendarManagement.fetch_integration_for_user(integration_id, user_id) do
      {:ok, integration} -> CalendarGrid.refresh_integration_events(integration)
      {:error, :not_found} -> :ok
    end

    :ok
  end

  defp refresh_booker_calendar(:nothing_written, _user_id), do: :ok
  defp refresh_booker_calendar(result, _user_id), do: result

  defp wants_copy?(%{booker_user_id: user_id} = meeting) when is_integer(user_id),
    do: MeetingState.expects_calendar_event?(meeting)

  defp wants_copy?(_meeting), do: false

  # The integration is nilified when it is removed, and the booker with it
  # when their account is, so a copy is only reachable while both remain.
  defp mapped?(%{booker_calendar_integration_id: integration_id, booker_user_id: user_id} = m)
       when is_integer(integration_id) and is_integer(user_id),
       do: is_binary(m.booker_calendar_event_id)

  defp mapped?(_meeting), do: false

  defp create_copy(meeting) do
    case BookerCalendar.target(meeting.booker_user_id) do
      nil ->
        Logger.info("Booker has no calendar that can take the meeting, skipping their copy",
          meeting_id: meeting.id
        )

        :nothing_written

      {integration, calendar} ->
        write_copy(meeting, %{
          booker_calendar_integration_id: integration.id,
          booker_calendar_id: calendar && calendar.id
        })
    end
  end

  # `location` is where the copy goes: the booker's connection and, when they
  # picked one, the calendar of it. It is recorded against the meeting as
  # loaded, so the update sees it as a change.
  defp write_copy(meeting, location) do
    context = meeting |> Map.merge(location) |> copy_context()

    case calendar_module().create_event(build_event_data(meeting), context) do
      {:ok, created} ->
        record_copy(meeting, location, created)

      # A retried create finds the copy an earlier attempt wrote, under the
      # same UID: it exists, so it is recorded and updated in place.
      {:error, :precondition_failed} ->
        record_copy(meeting, location, CreatedEvent.new(copy_uid(meeting)))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_copy(meeting, location, created) do
    attrs = Map.put(location, :booker_calendar_event_id, CreatedEvent.local_uid(created))

    case MeetingQueries.update_meeting(meeting, attrs) do
      {:ok, _meeting} ->
        Logger.info("Booker's calendar copy written", meeting_id: meeting.id)
        {:written, location.booker_calendar_integration_id}

      {:error, changeset} ->
        Logger.error("Could not record the booker's calendar copy, removing it",
          meeting_id: meeting.id,
          error: LogFormat.reason(changeset.errors)
        )

        delete_event(
          CreatedEvent.local_uid(created),
          meeting |> Map.merge(location) |> copy_context()
        )

        {:error, :booker_copy_not_recorded}
    end
  end

  defp update_copy(meeting) do
    case calendar_module().update_event(
           meeting.booker_calendar_event_id,
           build_event_data(meeting),
           copy_context(meeting)
         ) do
      :ok ->
        {:written, meeting.booker_calendar_integration_id}

      {:ok, _written} ->
        {:written, meeting.booker_calendar_integration_id}

      # Deleted from the booker's calendar meanwhile: written again, as the
      # organiser's own event is.
      {:error, :not_found} ->
        meeting |> forget_copy() |> create_copy()

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_copy(meeting) do
    case delete_event(meeting.booker_calendar_event_id, copy_context(meeting)) do
      :ok ->
        forget_copy(meeting)
        {:written, meeting.booker_calendar_integration_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp delete_event(event_id, context) do
    case calendar_module().delete_event(event_id, context) do
      result when result in [:ok, {:error, :not_found}] -> :ok
      {:ok, _deleted} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp forget_copy(meeting) do
    attrs = %{
      booker_calendar_integration_id: nil,
      booker_calendar_id: nil,
      booker_calendar_event_id: nil
    }

    case MeetingQueries.update_meeting(meeting, attrs) do
      {:ok, updated} ->
        updated

      {:error, changeset} ->
        Logger.warning("Could not clear the booker's calendar copy",
          meeting_id: meeting.id,
          error: LogFormat.reason(changeset.errors)
        )

        Map.merge(meeting, attrs)
    end
  end

  # A copy written before the booker picked a calendar, or with none picked,
  # sits on the connection's own booking calendar.
  defp copy_context(%{booker_calendar_id: calendar_id} = meeting) when is_binary(calendar_id),
    do: {meeting.booker_calendar_integration_id, meeting.booker_user_id, calendar_id}

  defp copy_context(meeting), do: {meeting.booker_calendar_integration_id, meeting.booker_user_id}

  @doc """
  The UID the booker's copy of `meeting` is written under: derived from the
  organiser's event UID, so it is stable across retries, yet never equal to
  it.
  """
  @spec copy_uid(MeetingSchema.t()) :: String.t()
  def copy_uid(meeting), do: meeting.calendar_uid <> "-booker"

  @doc """
  The event written to the booker's calendar, in the booker's language: the
  meeting as they see it, with whom it is, where, and the link to join.
  """
  @spec build_event_data(MeetingSchema.t()) :: map()
  def build_event_data(meeting) do
    Gettext.with_locale(TymeslotWeb.Gettext, booker_locale(meeting), fn ->
      %{
        uid: copy_uid(meeting),
        summary: DisplayTitle.attendee_title(meeting, booker_title_source(meeting)),
        description: build_description(meeting),
        start_time: meeting.start_time,
        end_time: meeting.end_time,
        timezone: meeting.attendee_timezone,
        location: meeting.meeting_url || meeting.location,
        conference_url: meeting.meeting_url,
        transparency: :opaque,
        status: if(MeetingState.awaiting_approval?(meeting), do: :tentative, else: :confirmed)
      }
    end)
  end

  # The copy lands in the booker's calendar, so their own "Name bookings by"
  # preference names it, as the organiser's names their event.
  defp booker_title_source(meeting),
    do: CalendarManagement.get_or_create_preferences(meeting.booker_user_id).booking_title_source

  # The booker's own language when their account sets one; otherwise the one
  # they booked in, rather than the instance default.
  defp booker_locale(meeting) do
    case Auth.get_user(meeting.booker_user_id) do
      {:ok, %{locale: locale}} when is_binary(locale) ->
        if Locales.acceptable?(locale), do: locale, else: meeting.attendee_locale

      _no_locale ->
        meeting.attendee_locale
    end
  end

  defp build_description(meeting) do
    [
      organizer_line(meeting),
      phone_line(meeting.organizer_phone),
      present(meeting.description),
      labelled(
        meeting.organizer_note,
        dgettext("emails", "Message from %{name}:", name: meeting.organizer_name)
      ),
      labelled(meeting.meeting_url, dgettext("emails", "Video meeting:"))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  # The host's email and phone appear only as far as they agreed to share them
  # when the meeting was booked (`MeetingType.show_email_to_bookers` and
  # `show_phone_to_bookers`, snapshot on the meeting).
  defp organizer_line(%{
         organizer_name: name,
         organizer_email: email,
         share_organizer_email: true
       }),
       do: dgettext("emails", "Organizer: %{organizer}", organizer: "#{name} <#{email}>")

  defp organizer_line(%{organizer_name: name}),
    do: dgettext("emails", "Organizer: %{organizer}", organizer: name)

  defp phone_line(phone) do
    case present(phone) do
      nil -> nil
      phone -> dgettext("emails", "Phone: %{phone}", phone: phone)
    end
  end

  defp labelled(value, label) do
    case present(value) do
      nil -> nil
      text -> label <> "\n" <> text
    end
  end

  defp present(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp present(_value), do: nil

  defp calendar_module do
    Application.get_env(:tymeslot, :calendar_module) ||
      Tymeslot.Integrations.Calendar.Events
  end
end
