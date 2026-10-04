defmodule Tymeslot.Bookings.MeetingPermissions do
  @moduledoc """
  Whether a meeting may be cancelled, rescheduled or deleted, and the clock
  checks behind those verdicts. `Tymeslot.Bookings.Policy` delegates here, so
  callers keep using the `Policy` functions.

  `can_cancel_meeting?/1` and `can_reschedule_meeting?/1` read the system clock
  (`Tymeslot.Clock`) and emit `Logger.info` on their blocked branches.
  `meeting_is_current?/1` and `meeting_is_past?/1` also read the clock but do no
  logging.
  """
  alias Tymeslot.Clock

  require Logger

  @typedoc "A meeting record with the fields required by the policy checks."
  @type meeting_record :: %{
          required(:status) => String.t(),
          required(:uid) => String.t(),
          required(:start_time) => DateTime.t(),
          required(:end_time) => DateTime.t(),
          optional(atom()) => term()
        }

  @doc """
  Determines if a meeting can be cancelled.
  Checks both status and time constraints.
  """
  @spec can_cancel_meeting?(meeting_record()) :: :ok | {:error, String.t()}
  def can_cancel_meeting?(meeting) do
    cond do
      meeting.status == "cancelled" ->
        {:error, "Meeting is already cancelled"}

      meeting.status == "completed" ->
        {:error, "Cannot cancel a completed meeting"}

      # An expired meeting (a lapsed approval request or an abandoned paid
      # checkout) has already been released: its slot was freed, the attendee
      # was told the request lapsed, and `Meetings.Approval` has already
      # refunded whatever was paid for it. Cancelling would overwrite that
      # outcome with `"cancelled"` and run the whole cancellation pipeline
      # over it — a second pair of emails contradicting the expiry notice, a
      # `meeting.cancelled` webhook for a meeting that never happened, and a
      # calendar delete for an event already removed. The request-received
      # email's withdraw link stays live in the invitee's inbox after the
      # deadline, so this is a reachable click, not a theoretical one.
      meeting.status == "expired" ->
        {:error, "Cannot cancel an expired meeting"}

      meeting_is_current?(meeting) ->
        Logger.info("Blocked cancellation: meeting has already started",
          meeting_uid: meeting.uid
        )

        {:error, "Cannot cancel a meeting that has already started"}

      meeting_is_past?(meeting) ->
        Logger.info("Blocked cancellation: meeting has already occurred",
          meeting_uid: meeting.uid
        )

        {:error, "Cannot cancel a meeting that has already occurred"}

      true ->
        :ok
    end
  end

  @doc """
  Determines if a meeting can be rescheduled.
  Checks both status and time constraints.
  """
  @spec can_reschedule_meeting?(meeting_record()) :: :ok | {:error, String.t()}
  def can_reschedule_meeting?(meeting) do
    cond do
      meeting.status == "cancelled" ->
        {:error, "Cannot reschedule a cancelled meeting"}

      meeting.status == "completed" ->
        {:error, "Cannot reschedule a completed meeting"}

      # An expired meeting (a lapsed approval request or an abandoned paid
      # checkout) has already released its slot: `MeetingState`'s
      # `@occupying_statuses` excludes "expired", so conflict detection ignores
      # it. Rescheduling would move it to a new time it does not reserve, and
      # the attendee would be told about a booking anyone else can still take.
      meeting.status == "expired" ->
        {:error, "Cannot reschedule an expired meeting"}

      meeting_is_current?(meeting) ->
        Logger.info("Blocked reschedule: meeting has already started", meeting_uid: meeting.uid)
        {:error, "Cannot reschedule a meeting that has already started"}

      meeting_is_past?(meeting) ->
        Logger.info("Blocked reschedule: meeting has already occurred", meeting_uid: meeting.uid)
        {:error, "Cannot reschedule a meeting that has already occurred"}

      true ->
        :ok
    end
  end

  @doc """
  Determines if the organiser may ask the attendee to pick a new time
  (`Tymeslot.Bookings.RescheduleRequest`, the host-initiated flow that voids
  the current slot and waits on the attendee).

  Distinct from `can_reschedule_meeting?/1`: that one also gates the
  attendee moving their own booking, including a still-held request, which
  is allowed. This one refuses a held request outright, because the host
  has no reschedule action until they have approved it — voiding the slot
  here would leave a request that still reads as approvable pointing at
  time that no longer holds.
  """
  @spec can_request_reschedule?(meeting_record()) :: :ok | {:error, String.t()}
  def can_request_reschedule?(%{status: "awaiting_approval"}) do
    {:error, "Cannot request a reschedule while the booking awaits approval"}
  end

  def can_request_reschedule?(meeting), do: can_reschedule_meeting?(meeting)

  @doc """
  Determines if a meeting can be manually (hard) deleted. Only already-
  cancelled meetings can be deleted this way — live, past, or pending
  meetings need their own status change first.
  """
  @spec can_delete_meeting?(meeting_record()) :: :ok | {:error, String.t()}
  def can_delete_meeting?(meeting) do
    if meeting.status == "cancelled" do
      :ok
    else
      {:error, "Only cancelled meetings can be deleted"}
    end
  end

  @doc """
  Checks if a meeting is currently happening.
  Pure function that compares meeting times with current UTC time.
  """
  @spec meeting_is_current?(%{
          required(:start_time) => DateTime.t(),
          required(:end_time) => DateTime.t(),
          optional(atom()) => term()
        }) :: boolean()
  def meeting_is_current?(%{start_time: start_time, end_time: end_time}) do
    now = Clock.utc_now()
    DateTime.compare(start_time, now) != :gt && DateTime.compare(end_time, now) == :gt
  end

  @doc """
  Checks if a meeting is in the past.
  Pure function that compares meeting end time with current UTC time.
  """
  @spec meeting_is_past?(%{required(:end_time) => DateTime.t(), optional(atom()) => term()}) ::
          boolean()
  def meeting_is_past?(%{end_time: end_time}) do
    DateTime.compare(end_time, Clock.utc_now()) == :lt
  end
end
