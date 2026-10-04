defmodule Tymeslot.Meetings.CalendarEventSync.Mapping do
  @moduledoc """
  Persists the mapping from a meeting to the calendar event created for it:
  which integration and calendar path hold the event, and the identifier the
  provider knows it by. Used by `Tymeslot.Meetings.CalendarEventSync`.
  """

  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Integrations.Calendar.CreatedEvent
  alias Tymeslot.Meetings.MeetingQueries
  alias Tymeslot.Meetings.MeetingSchema

  require Logger

  # Persist which integration and calendar path were used for creation. With
  # no integration to name, a plain create records nothing, as it always has;
  # a write that carries `base_attrs` still records the new event, since a
  # replacement must never leave the meeting on the event it is about to
  # delete.
  @spec persist(MeetingSchema.t(), CreatedEvent.t(), map(), module()) ::
          :ok | {:error, :calendar_mapping_persistence_failed}
  def persist(meeting, created, base_attrs, calendar_module) do
    case calendar_module.get_booking_integration_info(meeting) do
      {:ok, %{integration_id: integration_id, calendar_path: calendar_path}} ->
        attrs =
          Map.merge(base_attrs, %{
            calendar_integration_id: integration_id,
            calendar_path: calendar_path
          })

        write(meeting, put_provider_id(attrs, created))

      _no_integration_info when map_size(base_attrs) == 0 ->
        :ok

      _no_integration_info ->
        write(meeting, put_provider_id(base_attrs, created))
    end
  end

  defp write(meeting, attrs) do
    case MeetingQueries.update_meeting(meeting, attrs) do
      {:ok, _updated} ->
        :ok

      {:error, changeset} ->
        Logger.error("Failed to persist calendar mapping",
          meeting_id: meeting.id,
          error: LogFormat.reason(changeset.errors)
        )

        {:error, :calendar_mapping_persistence_failed}
    end
  end

  # A provider that reported an iCalendar UID (the CalDAV family) has confirmed
  # the value the meeting's event is keyed by, which is `calendar_uid`. It is
  # never written to `uid`: that is the booking's public identifier, already
  # embedded in the links the attendee was sent. Every other provider answers
  # with an identifier it minted, which belongs in `provider_event_id`:
  # writing it to `calendar_uid` would key the meeting by a value no sync ever
  # produces.
  #
  # A CalDAV create now also reports the resource's href, and that is
  # deliberately not persisted here. `calendar_event_identifier/1` hands
  # `provider_event_id` back as the uid of the next write, and an href is not
  # one. It belongs on the cached grid row, which addresses events by URL.
  defp put_provider_id(attrs, %CreatedEvent{uid: uid}) when is_binary(uid),
    do: Map.put(attrs, :calendar_uid, uid)

  defp put_provider_id(attrs, %CreatedEvent{provider_event_id: id}) when is_binary(id),
    do: Map.put(attrs, :provider_event_id, id)

  defp put_provider_id(attrs, %CreatedEvent{}), do: attrs
end
