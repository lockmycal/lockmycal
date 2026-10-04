defmodule Tymeslot.Meetings.DisplayTitle do
  @moduledoc """
  The single source of truth for what names a booking on the organiser's
  dashboard agenda and calendar grid, and for the title of the event written
  to their connected calendar (`CalendarEventBuilder.build_event_data/1`).

  The organiser picks the source in their profile (stored in
  `calendar_preferences.booking_title_source`):

    * `"meeting_info"` (the default) — the text the guest typed into the
      booking form's "Meeting Information" field (`attendee_message`), first
      non-blank line only, since the field is free-form and multi-line.
    * `"meeting_type"` — the booking's own title, built from the meeting type
      at booking time (e.g. "Consultation with Jane Doe").

  A booking without meeting information — the guest left it blank, or it was
  added by hand in the dashboard — always falls back to its own title.

  A booking the user made on someone else's page is named from their side
  (`attendee_title/2`), under their own preference: in their dashboard and in
  the copy written to their calendar (`Tymeslot.Meetings.BookerCalendarSync`).
  """

  alias Tymeslot.Bookings.BookingTitle

  @sources ~w(meeting_info meeting_type)
  @default_source "meeting_info"

  @doc "The sources a preference may store, in the order they are offered."
  @spec sources() :: [String.t()]
  def sources, do: @sources

  @doc "The source used when the organiser has not chosen one."
  @spec default_source() :: String.t()
  def default_source, do: @default_source

  @doc "Whether `source` is a title source this module understands."
  @spec valid?(term()) :: boolean()
  def valid?(source), do: source in @sources

  @doc """
  The display title of `meeting` under `source`. An unknown or `nil` source
  reads as the default.
  """
  @spec title(map(), String.t() | nil) :: String.t()
  def title(meeting, "meeting_type"), do: own_title(meeting)

  def title(meeting, _meeting_info) do
    first_line(Map.get(meeting, :attendee_message)) || own_title(meeting)
  end

  @doc """
  The display title, under `source`, of `meeting` as its attendee sees it: the
  meeting information they typed themselves, or "<meeting type> with
  <organiser>" in the current locale, as the booking's own title names the
  attendee instead.
  """
  @spec attendee_title(map(), String.t() | nil) :: String.t()
  def attendee_title(meeting, "meeting_type"), do: attendee_own_title(meeting)

  def attendee_title(meeting, _meeting_info) do
    first_line(Map.get(meeting, :attendee_message)) || attendee_own_title(meeting)
  end

  defp attendee_own_title(meeting),
    do: BookingTitle.render(Map.get(meeting, :meeting_type), Map.get(meeting, :organizer_name))

  defp own_title(meeting), do: presence(Map.get(meeting, :title)) || "Meeting"

  defp first_line(text) when is_binary(text) do
    text
    |> String.split(~r/\R/u)
    |> Enum.find_value(&presence/1)
  end

  defp first_line(_text), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil
end
