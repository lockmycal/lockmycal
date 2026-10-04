defmodule TymeslotWeb.Dashboard.CalendarGrid.UpdateHandlers do
  @moduledoc "Update action handlers for CalendarGridComponent."

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias Tymeslot.CalendarGrid
  alias Tymeslot.Meetings
  alias TymeslotWeb.Dashboard.CalendarGrid.DesktopReminderFeed
  alias TymeslotWeb.Dashboard.CalendarGrid.EditWorkflow
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.BookingDetail
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.CreateFormState
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.InlineEdit
  alias TymeslotWeb.Dashboard.CalendarGrid.EventWrites
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers

  @doc """
  Takes a failed write's change back off the grid. A write the grid queued
  (`:write` names it) is settled through `EventWrites`, which decides what the
  row shows; anything else reverts the row to `:original_event`.
  """
  @spec handle_revert_event(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_revert_event(%{write: {_key, _seq} = write}, socket),
    do: {:ok, EventWrites.settle(socket, write, :failed)}

  def handle_revert_event(%{original_event: original}, socket),
    do: {:ok, EventWrites.show(socket, original)}

  @doc "Records that a write the grid queued has answered without failing."
  @spec handle_event_write_settled(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_event_write_settled(%{write: write, outcome: outcome}, socket),
    do: {:ok, EventWrites.settle(socket, write, outcome)}

  @doc """
  Starts the edits kept for an event another LiveView has finished writing.
  """
  @spec handle_event_writes_released(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_event_writes_released(%{release: release}, socket),
    do: {:ok, EventWrites.resume(socket, release)}

  @spec handle_refresh_events(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_refresh_events(assigns, socket) do
    was_syncing = socket.assigns.syncing

    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:syncing, false)
      |> assign(:sync_total, 0)
      |> assign(:sync_completed, 0)
      |> Helpers.load_integrations()
      |> Helpers.load_events()

    if was_syncing, do: send(self(), :calendar_sync_flash)

    {:ok, socket}
  end

  @spec handle_reload_events(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_reload_events(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> Helpers.load_events()

    {:ok, socket}
  end

  @spec handle_ad_hoc_meeting_created(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_ad_hoc_meeting_created(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:creating_event, nil)
      |> assign(:saving_event, false)
      |> Helpers.load_events()

    {:ok, socket}
  end

  @spec handle_ad_hoc_meeting_failed(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_ad_hoc_meeting_failed(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:saving_event, false)

    {:ok, socket}
  end

  @spec handle_event_created(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_event_created(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:creating_event, nil)
      |> assign(:saving_event, false)
      |> Helpers.load_events()

    {:ok, socket}
  end

  @spec handle_event_create_failed(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_event_create_failed(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:saving_event, false)

    {:ok, socket}
  end

  @spec handle_event_moved(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_event_moved(assigns, socket) do
    new_uid = assigns[:new_event_uid]
    new_integration_id = assigns[:new_event_integration_id]

    socket =
      socket
      |> assign(Map.drop(assigns, [:action, :new_event_uid, :new_event_integration_id]))
      |> Helpers.load_events()

    new_event =
      Enum.find(socket.assigns.events, fn e ->
        e.uid == new_uid and e.calendar_integration_id == new_integration_id
      end)

    {:ok, assign(socket, :selected_event, new_event)}
  end

  @doc """
  Reloads the grid once a whole series has moved to another calendar, as
  after any write to a whole series (see `EventWrites.series_moved/2`): the
  series' rows are gone from the source, and its rows on the destination
  arrive with that calendar's sync.
  """
  @spec handle_series_moved(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_series_moved(%{moved_event: event} = assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action, :moved_event]))
      |> EventWrites.series_moved(event)

    {:ok, socket}
  end

  @doc """
  Makes the changes held while a whole series was moving, once the move
  has failed and left the series where it was.
  """
  @spec handle_series_move_failed(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_series_move_failed(%{moved_event: event} = assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action, :moved_event]))
      |> EventWrites.series_move_failed(event)

    {:ok, socket}
  end

  @spec handle_event_deleted(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_event_deleted(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:confirm_delete_event, nil)
      |> assign(:confirm_delete_linked_to_booking, false)
      |> assign(:deleting_event, false)
      |> assign(:selected_event, nil)
      |> Helpers.load_events()

    {:ok, socket}
  end

  @doc """
  Resets the confirmation after a delete the provider would not take.

  Reloads the events on purpose, because a refused delete can still have
  changed what the grid should show. A delete queued for retry leaves the
  cached row marked `locally_deleted` with no timing, so the reload drops the
  event the moment the flash says the delete is queued rather than leaving it
  on screen until an unrelated reload. A failure that was not queued leaves
  the row untouched, so the event stays where it was.
  """
  @spec handle_event_delete_failed(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_event_delete_failed(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:confirm_delete_event, nil)
      |> assign(:confirm_delete_linked_to_booking, false)
      |> assign(:deleting_event, false)
      |> Helpers.load_events()

    {:ok, socket}
  end

  @spec handle_events_updated(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_events_updated(assigns, socket) do
    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> Helpers.load_events()

    {:ok, socket}
  end

  @spec handle_integration_synced(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_integration_synced(assigns, socket) do
    total = socket.assigns.sync_total
    completed = socket.assigns.sync_completed + 1

    socket =
      socket
      |> assign(Map.drop(assigns, [:action]))
      |> assign(:sync_completed, completed)

    socket =
      cond do
        # User-initiated sync completed: reload everything and show flash.
        total > 0 and completed >= total ->
          send(self(), :calendar_sync_flash)

          socket
          |> assign(:syncing, false)
          |> assign(:sync_total, 0)
          |> assign(:sync_completed, 0)
          |> Helpers.load_integrations()
          |> Helpers.load_events()

        # Background sync (sweep worker): silently refresh events only.
        total == 0 ->
          socket
          |> assign(:sync_completed, 0)
          |> Helpers.load_events()

        # User-initiated sync still in progress.
        true ->
          socket
      end

    {:ok, socket}
  end

  @doc """
  Applies a finished video-room change to the loaded events and, when it is
  the open one, to the detail modal, then runs the same attendee-notification
  decision every other inline edit ends in.

  Only the three columns the change wrote are merged, rather than the updated
  event replacing what is on screen, so a sync that landed while the room was
  being provisioned is not rolled back. The description is one of them: the
  join link is written into it, and leaving it behind would show the previous
  link in the detail modal.
  """
  @spec handle_video_link_updated(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_video_link_updated(
        %{original_event: original, updated_event: updated} = assigns,
        socket
      ) do
    video = Map.take(updated, [:video_link, :video_integration_id, :description])

    updated_events =
      Enum.map(socket.assigns.events, fn e ->
        if e.id == updated.id, do: Map.merge(e, video), else: e
      end)

    selected = socket.assigns.selected_event

    socket =
      socket
      |> assign(:events, updated_events)
      |> then(fn s ->
        if selected && selected.id == updated.id,
          do: assign(s, :selected_event, Map.merge(selected, video)),
          else: s
      end)
      |> settle_video_write(assigns[:write], updated)

    {:ok,
     EditWorkflow.apply_notify_result(
       socket,
       original,
       updated,
       EditWorkflow.video_changed_message(updated.video_link)
     )}
  end

  defp settle_video_write(socket, nil, _updated), do: socket

  defp settle_video_write(socket, write, updated),
    do: EventWrites.settle(socket, write, {:ok, updated})

  @spec handle_initial(map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def handle_initial(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      cond do
        Map.get(socket.assigns, :_initialized) ->
          adopt_if_revived(socket)

        not connected?(socket) ->
          socket

        true ->
          Process.send_after(self(), :tick, 60_000)

          socket
          |> assign(:_initialized, true)
          |> Helpers.load_integrations()
          |> Helpers.assign_view_from_preferences()
          |> Helpers.assign_timezone()
          |> open_on_date()
          |> EventWrites.adopt()
          |> Helpers.load_events()
          |> maybe_auto_refresh()
          |> maybe_open_create_form()
          |> maybe_open_linked_entry()
      end

    {:ok, assign_desktop_reminder_feed(socket)}
  end

  # `/dashboard?date=YYYY-MM-DD` opens the grid on that day (an Overview agenda
  # entry links here with its own day); anything else opens on today.
  defp open_on_date(%{assigns: %{params: %{"date" => date}}} = socket) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, date} -> assign(socket, :date, date)
      {:error, _reason} -> open_on_today(socket)
    end
  end

  defp open_on_date(socket), do: open_on_today(socket)

  # LiveView revives a grid rendered again before the browser has confirmed
  # its removal: the organiser left the calendar and came straight back. It
  # still holds the queue it had when it left, which its guardian has been
  # driving since, so it takes the queue back as a grid mounted afresh does.
  defp adopt_if_revived(socket) do
    if socket.assigns[:calendar_left] == socket.assigns[:writes_adopted_after],
      do: socket,
      else: socket |> EventWrites.adopt() |> Helpers.load_events()
  end

  defp open_on_today(socket),
    do: assign(socket, :date, Helpers.today(socket.assigns.user_timezone))

  # `/dashboard?create=1` (the Overview's "Create a meeting" quick action)
  # arrives with the create-event modal already open, at the same default slot
  # as the Quick add button and the `c` shortcut. Only on the first connect, so
  # later patches and ticks never reopen a modal the user has closed.
  defp maybe_open_create_form(%{assigns: %{params: %{"create" => "1"}}} = socket) do
    {:noreply, socket} = CreateFormState.handle_show_create_form(%{}, socket)
    socket
  end

  defp maybe_open_create_form(socket), do: socket

  # An Overview agenda entry links to `/dashboard?event=<id>` (a synced event)
  # or `?booking=<meeting id>`, arriving with the same detail modal a click on
  # the grid opens; closing it goes back to the Overview. Only on the first
  # connect, like `maybe_open_create_form/1`.
  defp maybe_open_linked_entry(socket) do
    socket = open_linked_entry(socket)
    opened? = socket.assigns.selected_event != nil or socket.assigns.selected_booking != nil
    assign(socket, :return_to_overview, opened?)
  end

  defp open_linked_entry(%{assigns: %{params: %{"event" => id}}} = socket) when is_binary(id),
    do: open_event(socket, id)

  defp open_linked_entry(%{assigns: %{params: %{"booking" => meeting_id}}} = socket)
       when is_binary(meeting_id) do
    {:noreply, socket} =
      BookingDetail.handle_show_booking(%{"meeting-id" => meeting_id}, socket)

    if socket.assigns.selected_booking,
      do: socket,
      else: open_synced_booking(socket, meeting_id)
  end

  defp open_linked_entry(socket), do: socket

  # A booking synced to a connected calendar sits on the grid as its provider
  # copy (see `BookingEvents.list_for_range/5`), so that copy is what opens.
  # So does a booking the user made on someone else's page: the grid holds
  # only the user's own bookings, and that one is there as the copy written to
  # their calendar (`Tymeslot.Meetings.BookerCalendar`). The meeting only
  # names which of the user's own events to open.
  defp open_synced_booking(socket, meeting_id) do
    with {:ok, meeting} <-
           Meetings.get_meeting_for_user(meeting_id, socket.assigns.current_user.email),
         identifiers = Meetings.calendar_identifier_set([meeting]),
         %{id: event_id} <-
           Enum.find(
             socket.assigns.events,
             &(not Helpers.booking?(&1) and Meetings.linked_to_calendar_event?(&1, identifiers))
           ) do
      open_event(socket, to_string(event_id))
    else
      _not_on_grid -> socket
    end
  end

  defp open_event(socket, id) do
    {:noreply, socket} = InlineEdit.handle_show_event(%{"event-id" => id}, socket)
    socket
  end

  # Recomputes the upcoming desktop-reminder feed. Runs on the initial connect
  # and again on every 60s `current_time` tick (which routes through this same
  # handler), so the browser always has a fresh window of fire times without a
  # dedicated server timer. When the preference is off we assign an empty feed
  # so the hook stays inert.
  defp assign_desktop_reminder_feed(socket) do
    prefs = socket.assigns[:preferences]

    if (connected?(socket) and prefs) && prefs.desktop_reminders_enabled do
      now = socket.assigns[:current_time] || DateTime.utc_now()
      timezone = socket.assigns[:user_timezone] || "Etc/UTC"
      time_format = Helpers.time_format(socket.assigns)

      integrations = Map.get(socket.assigns, :integrations, [])

      feed =
        socket
        |> visible_integration_ids()
        |> CalendarGrid.list_upcoming_events_with_reminders(now, integrations)
        |> DesktopReminderFeed.build(now, timezone, time_format)

      assign(socket, :desktop_reminders_feed, feed)
    else
      assign(socket, :desktop_reminders_feed, [])
    end
  end

  defp visible_integration_ids(socket) do
    hidden = socket.assigns[:hidden_integration_ids] || []

    socket.assigns
    |> Map.get(:integrations, [])
    |> Enum.map(& &1.id)
    |> Enum.reject(&(&1 in hidden))
  end

  defp maybe_auto_refresh(socket) do
    if socket.assigns.stale_integrations != [] do
      user_id = socket.assigns.current_user.id

      result = CalendarGrid.refresh_events(user_id)

      case result do
        {:ok, %{enqueued: 0}} ->
          socket

        {:ok, %{enqueued: enqueued, skipped: skipped}} ->
          Process.send_after(self(), :reset_calendar_sync, 30_000)

          socket
          |> assign(:syncing, true)
          |> assign(:sync_total, enqueued + skipped)
          |> assign(:sync_completed, skipped)
      end
    else
      socket
    end
  end
end
