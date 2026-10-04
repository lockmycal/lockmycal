defmodule TymeslotWeb.Dashboard.BookingsManagement.QuickAddMeetingExecution do
  @moduledoc """
  Submits the Meetings page's "Quick add" dialog (`QuickAddMeeting`'s
  `creating_event`): a meeting mode books straight through
  `Tymeslot.Bookings.CreateAdHoc`; an event mode writes a bare event to the
  connected calendar through
  `Tymeslot.CalendarGrid.EventCreation.run_create_event/1` — a bare event
  never appears in this page's own meetings list (that list is Tymeslot
  bookings, not calendar events), same as it wouldn't in the calendar's own
  event list either.

  The meeting-mode path runs synchronously, matching this component's other
  actions (cancel/refuse/approve). The event-mode path instead mirrors the
  calendar's own Task-based plumbing (`CalendarEventHandlers.
  handle_execute_create_event/2`): a slow/hanging provider API call would
  otherwise block this whole LiveView process — not just "the grid", every
  other interaction on the page too — for as long as the call takes.
  `execute_event/2` spawns a supervised Task and returns immediately;
  `DashboardLive` routes the `{:quick_add_event_created, result}` message it
  sends back into `handle_event_create_result/2` via `send_update/2`.

  Split out of `QuickAddMeeting` purely to keep both modules under the
  dashboard page-size guideline. The validation/parsing/result-copy logic
  shared with `CalendarGrid.EventHandlers.CreateExecution` (same dialog,
  same rules) lives in `CalendarGrid.EventHandlers.Shared` and is called
  from both; only the flash mechanism differs and stays local — `Flash`
  forwards via a self-send since `put_flash/3` doesn't propagate from a
  LiveComponent, which is what this module runs inside and `CreateExecution`
  (running directly on `DashboardLive`'s own socket) doesn't need.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.Bookings.CreateAdHoc
  alias Tymeslot.CalendarGrid.EventCreation
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Infrastructure.Tasks
  alias Tymeslot.Meetings.Guests
  alias Tymeslot.Utils.ReminderUtils
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers, as: MeetingsHelpers
  alias TymeslotWeb.Dashboard.BookingsManagementComponent
  alias TymeslotWeb.Dashboard.CalendarGrid.EditWorkflow
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.CreateExecution
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared, as: CalendarGridShared
  alias TymeslotWeb.Dashboard.Shared.ContactPickerHandlers
  alias TymeslotWeb.Live.Shared.Flash

  require Logger

  @spec save_event(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def save_event(_params, socket) do
    case socket.assigns.creating_event do
      %{mode: :meeting} = creating -> save_meeting(socket, creating)
      creating -> save_calendar_event(socket, creating)
    end
  end

  # Private — meeting mode (books a Tymeslot meeting via CreateAdHoc)

  defp save_meeting(socket, creating) do
    timezone = MeetingsHelpers.get_meeting_timezone(nil, socket.assigns.profile)

    with :ok <-
           CalendarGridShared.authorize_optional_integration(socket, creating[:integration_id]),
         :ok <-
           CalendarGridShared.validate_meeting_fields(creating, socket.assigns.current_user.email),
         {:ok, start_at, end_at} <- resolve_timed_range(creating, timezone),
         {:ok, guest_emails} <- CreateExecution.extra_guest_emails(creating),
         :ok <- CalendarGridShared.check_quick_add_meeting_rate_limit(socket) do
      execute_meeting(socket, creating, timezone, start_at, end_at, guest_emails)
    else
      {:error, :unauthorized} ->
        Flash.error(dgettext("dashboard_calendar_events", "Invalid calendar selected"))
        {:noreply, socket}

      {:error, :rate_limited, message} ->
        Flash.error(message)
        {:noreply, socket}

      {:error, message} ->
        Flash.error(message)
        {:noreply, socket}
    end
  end

  defp resolve_timed_range(creating, timezone) do
    with {:ok, start_date} <- CalendarGridShared.parse_date(creating.date),
         {:ok, end_date} <- CalendarGridShared.parse_date(creating.end_date),
         {:ok, start_at} <-
           CalendarGridShared.to_utc_or_error(
             start_date,
             creating.start_hour,
             creating.start_minute,
             timezone
           ),
         {:ok, end_at} <-
           CalendarGridShared.to_utc_or_error(
             end_date,
             creating.end_hour,
             creating.end_minute,
             timezone
           ) do
      if DateTime.compare(end_at, start_at) == :gt do
        {:ok, start_at, end_at}
      else
        {:error, dgettext("dashboard_calendar_events", "End time must be after start time")}
      end
    end
  end

  defp execute_meeting(socket, creating, timezone, start_at, end_at, guest_emails) do
    current_user = socket.assigns.current_user
    guest_name = String.trim(creating.guest_name)

    params = %{
      title: String.trim(creating.title),
      start_time: start_at,
      end_time: end_at,
      attendee_name: guest_name,
      attendee_email: String.trim(creating.guest_email),
      attendee_timezone: timezone,
      organizer_user_id: current_user.id,
      calendar_integration_id: creating[:integration_id],
      calendar_path: creating[:calendar_id],
      video_integration_id: creating[:video_integration_id],
      reminders: ReminderUtils.from_calendar_reminders(creating[:reminders] || []),
      organizer_note: creating[:organizer_note],
      attendee_locale: creating[:locale],
      # `CreateAdHoc` expects a pre-validated list; the main guest can still be
      # typed in after being added as an extra one.
      guest_emails: Guests.sanitize_emails(guest_emails, creating.guest_email)
    }

    case CreateAdHoc.execute(params) do
      {:ok, _meeting} ->
        Flash.info(dgettext("dashboard_calendar_events", "Meeting created and invitation sent"))
        {:noreply, socket |> assign(:filter, "upcoming") |> close_after_save()}

      {:error, reason} ->
        Logger.error("quick_add_meeting_failed",
          reason: LogFormat.reason(reason),
          organizer_user_id: current_user.id
        )

        Flash.error(reason)
        {:noreply, socket}
    end
  end

  # Private — event mode (writes a bare event to the connected calendar,
  # mirroring `CalendarGrid.EventHandlers.CreateExecution` end to end)

  defp save_calendar_event(socket, creating) do
    case EditWorkflow.assert_owns_integration(socket, creating.integration_id) do
      {:error, :unauthorized} ->
        Flash.error(dgettext("dashboard_calendar_events", "Invalid calendar selected"))
        {:noreply, socket}

      :ok ->
        with :ok <- CalendarGridShared.validate_event_title(creating),
             {:ok, start_date} <- CalendarGridShared.parse_date(creating.date),
             {:ok, end_date} <- CalendarGridShared.parse_date(creating.end_date) do
          save_event_resolved(socket, creating, start_date, end_date)
        else
          {:error, message} ->
            Flash.error(message)
            {:noreply, socket}
        end
    end
  end

  defp save_event_resolved(socket, %{all_day: true} = creating, start_date, end_date) do
    if Date.compare(end_date, start_date) == :lt do
      Flash.error(dgettext("dashboard_calendar_events", "End date must not be before start date"))

      {:noreply, socket}
    else
      execute_event(socket, %{
        creating: creating,
        user_id: socket.assigns.current_user.id,
        start_at: start_date,
        end_at: Date.add(end_date, 1)
      })
    end
  end

  defp save_event_resolved(socket, creating, start_date, end_date) do
    tz = MeetingsHelpers.get_meeting_timezone(nil, socket.assigns.profile)

    with {:ok, start_at} <-
           CalendarGridShared.to_utc_or_error(
             start_date,
             creating.start_hour,
             creating.start_minute,
             tz
           ),
         {:ok, end_at} <-
           CalendarGridShared.to_utc_or_error(
             end_date,
             creating.end_hour,
             creating.end_minute,
             tz
           ) do
      if DateTime.compare(end_at, start_at) == :gt do
        execute_event(socket, %{
          creating: creating,
          user_id: socket.assigns.current_user.id,
          start_at: start_at,
          end_at: end_at
        })
      else
        Flash.error(dgettext("dashboard_calendar_events", "End time must be after start time"))
        {:noreply, socket}
      end
    else
      {:error, message} ->
        Flash.error(message)
        {:noreply, socket}
    end
  end

  # Spawns a supervised Task rather than calling EventCreation.run_create_event/1
  # inline, mirroring CalendarEventHandlers.handle_execute_create_event/2 —
  # both write to the same external calendar provider, and a slow/hanging API
  # call must not block this whole LiveView process while it's in flight.
  # DashboardLive routes the result back via send_update/2 (see
  # handle_event_create_result/2 below), since a LiveComponent has no
  # process of its own to receive the Task's message directly.
  defp execute_event(socket, payload) do
    lv_pid = self()

    Tasks.start_child(Tymeslot.TaskSupervisor, fn ->
      send(lv_pid, {:quick_add_event_created, EventCreation.run_create_event(payload)})
    end)

    {:noreply, assign(socket, :saving_event, true)}
  end

  @doc """
  Handles the async result of `execute_event/2`'s Task — reached via
  `DashboardLive`'s `{:quick_add_event_created, result}` handle_info,
  `send_update/2`-ed into `update(%{action: :quick_add_event_created, ...})`.
  """
  @spec handle_event_create_result(any(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event_create_result(result, socket) do
    socket = assign(socket, :saving_event, false)

    case result do
      {:ok, result} ->
        socket
        |> Flash.put_flash(:info, CalendarGridShared.flash_for_create(result.attendees))
        |> maybe_flash_warning(result[:warning])
        |> maybe_flash_reauth(result[:reauth_required])
        |> close_after_save()

      {:error, failure} ->
        Flash.error(create_failed_message(failure))
        socket
    end
  end

  # A queued create will be replayed on the next sync; anything else is final.
  defp create_failed_message(%{retry: :queued}),
    do: dgettext("dashboard_calendar_events", "Create failed - queued to retry on next sync")

  defp create_failed_message(_failure),
    do: dgettext("dashboard_calendar_events", "Failed to create event")

  defp maybe_flash_warning(socket, nil), do: socket
  defp maybe_flash_warning(socket, msg), do: Flash.put_flash(socket, :warning, msg)

  defp maybe_flash_reauth(socket, true),
    do: Flash.put_flash(socket, :error, EventCreation.reauth_flash_message())

  defp maybe_flash_reauth(socket, _other), do: socket

  defp close_after_save(socket) do
    socket
    |> assign(:creating_event, nil)
    |> ContactPickerHandlers.reset()
    |> BookingsManagementComponent.load_meetings()
  end
end
