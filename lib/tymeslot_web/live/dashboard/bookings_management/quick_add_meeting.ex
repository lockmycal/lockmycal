defmodule TymeslotWeb.Dashboard.BookingsManagement.QuickAddMeeting do
  @moduledoc """
  The Meetings page's own "Quick add" form-state handlers: reuses the
  calendar's own create-event dialog
  (`TymeslotWeb.Dashboard.CalendarGrid.Modals.CreateEventModal`) verbatim —
  same Event/Meeting toggle, same connected calendars/video providers,
  recurrence, reminders, free-form attendee list, and the "pick from
  contacts" shortcut. Submitting the form is handled by
  `QuickAddMeetingExecution`, split out purely to keep this module (and that
  one) under the dashboard page-size guideline.

  Event names (`show_create_form`, `update_create_guest_name`, ...)
  intentionally match `CalendarGrid.EventHandlers.CreateFormState` one for
  one, since they're dictated by the reused modal's own markup — the plain
  field-update handlers below delegate to `CreateFormState` outright (same
  `creating_event`/`integrations` assign shape as the calendar's own
  dialog); the rest have real Meetings-page-specific behaviour (lazy
  integration loading, this page's own timezone source, no "click a grid
  cell" entry point) and stay local.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.CalendarGrid
  alias Tymeslot.Contacts
  alias Tymeslot.Integrations.Video
  alias Tymeslot.Utils.DateTimeUtils
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers, as: MeetingsHelpers
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.CreateFormState
  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared, as: CalendarGridShared
  alias TymeslotWeb.Dashboard.Shared.ContactPickerHandlers

  @spec mount_defaults(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def mount_defaults(socket) do
    socket
    |> assign(:creating_event, nil)
    |> assign(:saving_event, false)
    |> assign(:integrations, [])
    |> assign(:integration_colors, %{})
    |> assign(:video_integrations, [])
    |> assign(:owned_integration_ids, MapSet.new())
    |> assign(:confirm_discard_attendees, false)
    |> ContactPickerHandlers.reset()
  end

  @spec show_create_form(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def show_create_form(_params, socket) do
    socket = load_integrations(socket)

    {:noreply,
     socket
     |> assign(:creating_event, default_creating_event(socket))
     |> ContactPickerHandlers.reset()}
  end

  @spec close_create_form(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def close_create_form(_params, socket) do
    creating = socket.assigns.creating_event

    if creating && (creating[:attendees] || []) != [] do
      {:noreply, assign(socket, :confirm_discard_attendees, true)}
    else
      {:noreply, socket |> assign(:creating_event, nil) |> ContactPickerHandlers.reset()}
    end
  end

  @spec discard_pending_attendees(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def discard_pending_attendees(_params, socket) do
    {:noreply,
     socket
     |> assign(:creating_event, nil)
     |> assign(:confirm_discard_attendees, false)
     |> ContactPickerHandlers.reset()}
  end

  @spec cancel_discard_attendees(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def cancel_discard_attendees(_params, socket),
    do: {:noreply, assign(socket, :confirm_discard_attendees, false)}

  # These field-update handlers have no Meetings-page-specific behaviour —
  # same `creating_event`/`integrations` assign shape as the calendar's own
  # dialog, so they delegate to `CreateFormState` outright instead of
  # duplicating its logic (matches `CalendarGrid.EventHandlers.EventCrud`'s
  # own facade convention for the same functions).
  defdelegate set_create_mode(params, socket), to: CreateFormState, as: :handle_set_create_mode

  defdelegate update_create_title(params, socket),
    to: CreateFormState,
    as: :handle_update_create_title

  defdelegate update_create_guest_name(params, socket),
    to: CreateFormState,
    as: :handle_update_create_guest_name

  defdelegate update_create_guest_email(params, socket),
    to: CreateFormState,
    as: :handle_update_create_guest_email

  defdelegate toggle_create_note(params, socket),
    to: CreateFormState,
    as: :handle_toggle_create_note

  defdelegate update_create_note(params, socket),
    to: CreateFormState,
    as: :handle_update_create_note

  defdelegate add_create_guest(params, socket),
    to: CreateFormState,
    as: :handle_add_create_guest

  defdelegate remove_create_guest(params, socket),
    to: CreateFormState,
    as: :handle_remove_create_guest

  defdelegate update_create_guest_input(params, socket),
    to: CreateFormState,
    as: :handle_update_create_guest_input

  defdelegate update_create_locale(params, socket),
    to: CreateFormState,
    as: :handle_update_create_locale

  defdelegate toggle_create_all_day(params, socket),
    to: CreateFormState,
    as: :handle_toggle_create_all_day

  defdelegate update_create_time(params, socket),
    to: CreateFormState,
    as: :handle_update_create_time

  defdelegate update_create_integration(params, socket),
    to: CreateFormState,
    as: :handle_update_create_integration

  defdelegate update_create_video(params, socket),
    to: CreateFormState,
    as: :handle_update_create_video

  defdelegate update_create_recurrence(params, socket),
    to: CreateFormState,
    as: :handle_update_create_recurrence

  defdelegate add_create_reminder(params, socket),
    to: CreateFormState,
    as: :handle_add_create_reminder

  defdelegate remove_create_reminder(params, socket),
    to: CreateFormState,
    as: :handle_remove_create_reminder

  defdelegate add_create_attendee(params, socket),
    to: CreateFormState,
    as: :handle_add_create_attendee

  defdelegate remove_create_attendee(params, socket),
    to: CreateFormState,
    as: :handle_remove_create_attendee

  defdelegate update_create_attendee_input(params, socket),
    to: CreateFormState,
    as: :handle_update_create_attendee_input

  @spec query_contacts(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def query_contacts(params, socket),
    do: ContactPickerHandlers.query(params, socket, socket.assigns.current_user.id)

  @spec close_contact_picker(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def close_contact_picker(_params, socket), do: ContactPickerHandlers.close(socket)

  @spec select_contact(map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def select_contact(%{"id" => id}, socket) do
    organizer_id = socket.assigns.current_user.id

    with {contact_id, ""} <- Integer.parse(id),
         {:ok, contact} <- Contacts.get_contact(contact_id, organizer_id) do
      socket =
        socket
        |> put_field(:guest_name, contact.name)
        |> put_field(:guest_email, contact.email)
        |> ContactPickerHandlers.reset()

      {:noreply, socket}
    else
      _not_selectable -> {:noreply, socket}
    end
  end

  # Private

  # Guarded once here rather than at each of select_contact/2's two call
  # sites: a stray/late phx-change/click event delivered after the dialog
  # has already been closed (creating_event reset to nil) is a no-op, same
  # as every other handler in this module.
  defp put_field(%{assigns: %{creating_event: nil}} = socket, _key, _value), do: socket

  defp put_field(socket, key, value) do
    assign(socket, :creating_event, Map.put(socket.assigns.creating_event, key, value))
  end

  # Same underlying calendar/video lookups as
  # `CalendarGrid.Helpers.DataLoading.load_integrations/1`, so the reused
  # dialog offers exactly what the calendar's own "Quick add" does.
  defp load_integrations(socket) do
    user_id = socket.assigns.current_user.id
    integrations = CalendarGrid.list_active_integrations(user_id)

    video_integrations =
      user_id
      |> Video.list_integrations()
      |> Enum.filter(& &1.is_active)

    socket
    |> assign(:integrations, integrations)
    |> assign(:integration_colors, CalendarGrid.integration_colour_classes(integrations))
    |> assign(:video_integrations, video_integrations)
    |> assign(:owned_integration_ids, MapSet.new(integrations, & &1.id))
  end

  # Defaults to the next whole hour in the organiser's dashboard timezone —
  # the only override this page ever needs, having no grid to click a start
  # time from. `Shared.base_creating/2` fills everything else (first
  # connected calendar/its default booking calendar pre-selected, meeting
  # mode when there's nothing to write a bare event to, ...), same as the
  # calendar's own dialog.
  defp default_creating_event(socket) do
    timezone = MeetingsHelpers.get_meeting_timezone(nil, socket.assigns.profile)
    now = DateTimeUtils.convert_to_timezone(DateTime.utc_now(), timezone)
    start_hour = if now.minute == 0, do: now.hour, else: rem(now.hour + 1, 24)
    today = DateTime.to_date(now)

    # start_hour + 1 unwrapped (can be 24) so clamp_end_time/3 rolls end_date
    # to tomorrow when the default one-hour slot starts at 23:00 — rem/2
    # would wrap the hour back to 0 while leaving end_date on today, making
    # the slot end before it starts.
    {end_date, end_hour, end_minute} = CalendarGridShared.clamp_end_time(today, start_hour + 1, 0)

    CalendarGridShared.base_creating(socket, %{
      date: Date.to_iso8601(today),
      end_date: Date.to_iso8601(end_date),
      start_hour: start_hour,
      start_minute: 0,
      end_hour: end_hour,
      end_minute: end_minute
    })
  end
end
