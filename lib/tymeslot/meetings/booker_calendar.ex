defmodule Tymeslot.Meetings.BookerCalendar do
  @moduledoc """
  A signed-in booker's copy of the meeting in their own calendar.

  When someone with an account books on another user's page, the booking form
  offers to write the meeting into their default calendar as well (the
  primary calendar integration and the calendar of it they picked, see
  `Tymeslot.Integrations.CalendarPrimary.set_default_calendar/3`).
  Their answer can be remembered on their profile
  (`save_bookings_to_own_calendar`): `:ask` shows the choice, `:always` and
  `:never` apply it without asking.

  The copy is kept in step with the meeting by
  `Tymeslot.Workers.BookerCalendarEventWorker`, which
  `Tymeslot.Workers.CalendarEventWorker` enqueues alongside every write to the
  organiser's calendar (`follow/1`), so whatever moves or cancels the meeting
  moves or removes the copy too.

  A booker without a calendar that can take a booking is never offered the
  copy and never gets one: the confirmation email's `.ics` stays their way to
  add it, as it is for everybody else.
  """

  alias Ecto.UUID
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.CalendarEntry
  alias Tymeslot.Integrations.Calendar.Runtime.BookingIntegrationResolver
  alias Tymeslot.Meetings.MeetingCalendarQueries
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Workers.BookerCalendarEventWorker

  require Logger

  @type choice :: :ask | :always | :never
  @type offer :: %{calendar_name: String.t(), choice: choice()}

  @choices [:ask, :always, :never]

  @doc "The values `save_bookings_to_own_calendar` can take."
  @spec choices() :: [choice()]
  def choices, do: @choices

  @doc """
  What the booking form offers `booker_user_id` when booking with
  `organizer_user_id`: the name of the calendar the copy would go to and the
  booker's remembered choice. `nil` when there is nothing to offer — nobody
  signed in, the organiser booking on their own page, or no calendar of the
  booker's that can take the booking.
  """
  @spec offer(integer() | nil, integer() | nil) :: offer() | nil
  def offer(booker_user_id, organizer_user_id)
      when is_integer(booker_user_id) and booker_user_id != organizer_user_id do
    with {integration, calendar} <- target(booker_user_id),
         {:ok, profile} <- ProfileQueries.get_by_user_id(booker_user_id) do
      %{
        calendar_name: calendar_name(integration, calendar),
        choice: profile.save_bookings_to_own_calendar
      }
    else
      _nothing_to_offer -> nil
    end
  end

  def offer(_booker_user_id, _organizer_user_id), do: nil

  @doc """
  Where `user_id`'s copies are written: the connection that takes their
  bookings and the calendar of it they picked as their default, `nil` for
  the connection's own booking calendar. `nil` altogether when no calendar of
  theirs can take a booking.
  """
  @spec target(integer()) :: {map(), CalendarEntry.t() | nil} | nil
  def target(user_id) do
    case BookingIntegrationResolver.resolve(user_id) do
      nil -> nil
      integration -> {integration, picked_calendar(integration, user_id)}
    end
  end

  # The pick only holds within the connection it was made in, and only while
  # that calendar can still take a booking; otherwise the connection's own
  # booking calendar does.
  defp picked_calendar(%{id: integration_id} = integration, user_id) do
    case ProfileQueries.get_by_user_id(user_id) do
      {:ok, %{primary_calendar_integration_id: ^integration_id, default_calendar_id: id}}
      when is_binary(id) ->
        Enum.find(Calendar.writable_calendars(integration.calendar_list), &(&1.id == id))

      _no_pick ->
        nil
    end
  end

  defp calendar_name(integration, nil), do: integration.name
  defp calendar_name(integration, calendar), do: "#{integration.name} – #{calendar.name}"

  @doc """
  Whether the booker gets the copy, given the form's offer and what they
  ticked (`save`), and the choice to remember for next time, if they asked
  for it to be remembered. A remembered choice applies as it stands.
  """
  @spec consent(offer() | nil, boolean(), boolean()) :: {boolean(), choice() | nil}
  def consent(nil, _save, _remember), do: {false, nil}
  def consent(%{choice: :always}, _save, _remember), do: {true, nil}
  def consent(%{choice: :never}, _save, _remember), do: {false, nil}
  def consent(%{choice: :ask}, save, true), do: {save, if(save, do: :always, else: :never)}
  def consent(%{choice: :ask}, save, false), do: {save, nil}

  @doc "The user's remembered choice."
  @spec choice(integer()) :: choice()
  def choice(user_id) do
    case ProfileQueries.get_by_user_id(user_id) do
      {:ok, profile} -> profile.save_bookings_to_own_calendar
      {:error, :not_found} -> :ask
    end
  end

  @doc "Remembers the user's choice."
  @spec remember(integer(), choice()) :: :ok | {:error, term()}
  def remember(user_id, choice) when choice in @choices do
    case ProfileQueries.set_save_bookings_to_own_calendar(user_id, choice) do
      {:ok, _profile} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Brings the booker's copy of `meeting_id` in step with the meeting, when it
  has one to keep. Called for every write to the organiser's calendar.
  """
  @spec follow(term()) :: :ok
  def follow(meeting_id) do
    # The organiser's job answers a malformed id itself; it is not ours to fail.
    with {:ok, id} <- UUID.cast(meeting_id),
         true <- MeetingCalendarQueries.booker_copy_tracked?(id) do
      schedule_sync(id)
    else
      _no_copy -> :ok
    end
  end

  @doc "Enqueues a sync of the booker's copy of `meeting_id`."
  @spec schedule_sync(String.t()) :: :ok
  def schedule_sync(meeting_id) do
    case meeting_id |> BookerCalendarEventWorker.new_sync() |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not schedule the booker's calendar sync",
          meeting_id: meeting_id,
          reason: LogFormat.reason(reason)
        )

        :ok
    end
  end
end
