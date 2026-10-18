defmodule TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared do
  @moduledoc "Shared helpers used across EventHandlers submodules."

  use Gettext, backend: TymeslotWeb.Gettext
  use TymeslotWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2]

  alias Tymeslot.Clock
  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.EventColour
  alias Tymeslot.Locales
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.Guests
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.Utils.DateTimeUtils
  alias TymeslotWeb.Components.Shared.ReminderPickerState
  alias TymeslotWeb.Dashboard.CalendarGrid.EditWorkflow
  alias TymeslotWeb.Dashboard.CalendarGrid.Helpers

  @doc """
  Sends the user back to the Overview after closing a detail modal that an
  Overview agenda link opened (`return_to_overview`, set by
  `UpdateHandlers.maybe_open_linked_entry/1`); any other close stays on the
  calendar. The flag is spent on the first close.
  """
  @spec close_linked_detail(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def close_linked_detail(%{assigns: %{return_to_overview: true}} = socket) do
    socket
    |> assign(:return_to_overview, false)
    |> push_navigate(to: ~p"/dashboard/overview")
  end

  def close_linked_detail(socket), do: socket

  @spec parse_int(binary()) :: {:ok, integer()} | :error
  @spec parse_int(term()) :: :error
  def parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {value, ""} -> {:ok, value}
      _other -> :error
    end
  end

  def parse_int(_not_binary), do: :error

  # Normalises an incoming colour-picker value to a stored colour. A recognised
  # palette key passes through unchanged; the "default" sentinel, an empty
  # string, or any unrecognised value clears the override (`nil`).
  @spec parse_colour(term()) :: String.t() | nil
  def parse_colour(value) do
    if EventColour.valid_key?(value), do: value, else: nil
  end

  # Constructs a UTC DateTime from a date and time in the user's display timezone.
  # The calendar grid renders events in the user's timezone, so drag/drop/create
  # coordinates are in that timezone and must be converted back to UTC for storage.
  #
  # DST gaps and overlaps resolve by `DateTimeUtils.resolve_local/3`, the rule
  # every other wall-clock conversion uses. An unknown timezone is returned as
  # `{:error, reason}` so callers can surface a flash instead of crashing the
  # LiveView.
  @spec to_utc(Date.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
          {:ok, DateTime.t()} | {:error, term()}
  def to_utc(date, hour, minute, timezone) do
    time = Time.new!(hour, minute, 0, {0, 6})

    with {:ok, local} <- DateTimeUtils.resolve_local(date, time, timezone) do
      {:ok, DateTime.shift_zone!(local, "Etc/UTC")}
    end
  end

  @spec clamp_end_time(Date.t(), non_neg_integer(), non_neg_integer()) ::
          {Date.t(), non_neg_integer(), non_neg_integer()}
  def clamp_end_time(date, hour, minute) when hour >= 24 do
    {Date.add(date, 1), 0, minute}
  end

  def clamp_end_time(date, hour, minute), do: {date, hour, minute}

  @spec check_edit_rate_limit(Phoenix.LiveView.Socket.t()) ::
          :ok | {:error, :rate_limited, String.t()}
  def check_edit_rate_limit(socket) do
    user_id = socket.assigns.current_user.id

    case RateLimiter.check_calendar_event_edit_rate_limit(user_id) do
      :ok -> :ok
      {:error, :rate_limited, message} -> {:error, :rate_limited, message}
    end
  end

  @spec check_move_rate_limit(Phoenix.LiveView.Socket.t()) ::
          :ok | {:error, :rate_limited, String.t()}
  def check_move_rate_limit(socket) do
    user_id = socket.assigns.current_user.id

    case RateLimiter.check_calendar_event_move_rate_limit(user_id) do
      :ok -> :ok
      {:error, :rate_limited, message} -> {:error, :rate_limited, message}
    end
  end

  @spec check_quick_add_meeting_rate_limit(Phoenix.LiveView.Socket.t()) ::
          :ok | {:error, :rate_limited, String.t()}
  def check_quick_add_meeting_rate_limit(socket) do
    user_id = socket.assigns.current_user.id

    case RateLimiter.check_dashboard_quick_add_meeting_rate_limit(user_id) do
      :ok -> :ok
      {:error, :rate_limited, message} -> {:error, :rate_limited, message}
    end
  end

  # The domain's rule rather than a copy of it: an address the form accepts
  # has to be one `Meetings.Guests` keeps, or it is dropped after the host was
  # told it was fine.
  @spec valid_email?(term()) :: boolean()
  def valid_email?(email), do: Guests.valid_email?(email)

  @doc """
  Computes the updated `creating_event` map for an Event/Meeting mode-toggle
  click, or `nil` when the toggle is a no-op: no `creating_event` yet, an
  unrecognised `mode` value, or switching to "event" with no calendar that
  can be written to (a subscription can be read and never written).

  Shared by the calendar's own `CreateFormState.handle_set_create_mode/2`
  and the Meetings page's `BookingsManagement.QuickAddMeeting.set_create_mode/2`,
  since both drive the same reused create-event dialog.
  """
  @spec toggle_create_mode(map() | nil, String.t(), list()) :: map() | nil
  def toggle_create_mode(nil, _mode, _integrations), do: nil

  def toggle_create_mode(_creating, mode, _integrations) when mode not in ~w(event meeting),
    do: nil

  def toggle_create_mode(creating, "meeting", _integrations),
    do: creating |> Map.put(:mode, :meeting) |> Map.put(:all_day, false)

  def toggle_create_mode(creating, "event", integrations) do
    if writable?(integrations), do: Map.put(creating, :mode, :event), else: nil
  end

  defp writable?(integrations), do: Calendar.writable_integrations(integrations) != []

  # Allowed reminder lead times (minutes before the event start) offered as
  # presets in the editor. Values outside this set are rejected so the UI
  # cannot feed arbitrary integers into the provider write.
  @reminder_minutes_presets [5, 10, 30, 60, 1440]

  @doc """
  Returns the allowed reminder lead times (minutes before the event start).
  This is the single source of truth for the preset whitelist: `parse_reminder/1`
  rejects anything outside it, and `RemindersEditor` builds the editor's options
  from this list rather than duplicating the values.
  """
  @spec reminder_minutes_presets() :: [pos_integer()]
  def reminder_minutes_presets, do: @reminder_minutes_presets

  @doc """
  Parses a reminder from `phx-value-method` / `phx-value-minutes` params into the
  canonical `%{method: :popup | :email, minutes_before: integer}` shape. Returns
  `:error` for an unknown method or a lead time outside the allowed presets.
  """
  @spec parse_reminder(map()) :: {:ok, %{method: atom(), minutes_before: pos_integer()}} | :error
  def parse_reminder(params) do
    with {:ok, method} <- parse_reminder_method(params["method"]),
         {:ok, minutes} <- parse_int(params["minutes"]),
         true <- minutes in @reminder_minutes_presets do
      {:ok, %{method: method, minutes_before: minutes}}
    else
      _invalid -> :error
    end
  end

  defp parse_reminder_method("popup"), do: {:ok, :popup}
  defp parse_reminder_method("email"), do: {:ok, :email}
  defp parse_reminder_method(_other), do: :error

  # ---------------------------------------------------------------------------
  # Refactor 1 — optimistic-update plumbing
  # ---------------------------------------------------------------------------

  @doc """
  Replaces the event whose `id` matches `id` in `events` with `new_event`.
  Events whose id does not match are kept unchanged.
  """
  @spec replace_event([map()], integer(), map()) :: [map()]
  def replace_event(events, id, new_event) do
    Enum.map(events, fn e -> if e.id == id, do: new_event, else: e end)
  end

  @doc """
  Applies a standard optimistic-update cycle on the socket and fires an async
  update.

  Steps (order preserved from original `push_*` private functions in
  `InlineEdit`):
    1. Replace the event in `:events` by id.
    2. Assign `:selected_event` with the optimistic event.
    3. Assign `:events` with the updated list.
    4. Run `Helpers.precompute_derived/1`.
    5. Call `async_fun.(socket)` — the async function receives the
       post-assign socket and returns it after scheduling the task.

  Returns `{:noreply, socket}` — the standard LiveView reply tuple.
  """
  @spec apply_optimistic_update(
          Phoenix.LiveView.Socket.t(),
          map(),
          (Phoenix.LiveView.Socket.t() -> Phoenix.LiveView.Socket.t())
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def apply_optimistic_update(socket, optimistic_event, async_fun) do
    updated_events =
      replace_event(socket.assigns.events, optimistic_event.id, optimistic_event)

    socket =
      socket
      |> assign(:selected_event, optimistic_event)
      |> assign(:events, updated_events)
      |> Helpers.precompute_derived()
      |> async_fun.()

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Refactor 2 — shared guard-error flash handler
  # ---------------------------------------------------------------------------

  @doc """
  Sends a flash message for guard errors that are duplicated across handlers
  and returns `{:noreply, socket}`.

  Handled errors:

    * `{:error, :unauthorized}` — "You don't have permission to modify this event"
    * `{:error, :read_only}` — "This calendar is read-only..."
    * `{:error, :rate_limited, _message}` — "Too many edits. Please wait a moment."
    * `{:error, :group_booking}` — a group meeting with live seats sits on the event
      (`check_seat_lock/2`)
    * `{:error, :until_before_start}` — the recurrence ends before the event starts

  Flash messages are sent via `send(self(), {:flash, ...})` (the LiveComponent
  pattern; `put_flash/3` does not propagate from LiveComponents).
  """
  @spec flash_guard_error(Phoenix.LiveView.Socket.t(), term()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def flash_guard_error(socket, error), do: {:noreply, flash_guard(socket, error)}

  # ---------------------------------------------------------------------------
  # Refactor 3 — optional int parsing and reminder-list helpers
  # ---------------------------------------------------------------------------

  @doc """
  Parses an optional integer from a string, binary, or integer value.

  Returns an integer when the input is a non-empty string that parses cleanly,
  or an integer passed through. Returns `nil` for `nil`, `""`, or any value
  that does not parse as a bare integer.

  Identical logic to the private `parse_video_integration_id/1` in
  `InlineEdit` and `maybe_put_int/3` in `CreateFormState`.
  """
  @spec parse_optional_int(nil | binary() | integer()) :: integer() | nil
  def parse_optional_int(nil), do: nil
  def parse_optional_int(""), do: nil

  def parse_optional_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _other -> nil
    end
  end

  def parse_optional_int(val) when is_integer(val), do: val
  def parse_optional_int(_other), do: nil

  @doc """
  Adds `reminder` to `reminders` if it is not already present (dedup).

  Returns the updated list unchanged when `reminder` is already in it.
  """
  @spec add_reminder([map()], map()) :: [map()]
  def add_reminder(reminders, reminder) do
    if reminder in reminders, do: reminders, else: reminders ++ [reminder]
  end

  # ---------------------------------------------------------------------------
  # Refactor 4 — create-event/ad-hoc-meeting validation and result helpers,
  # shared by CreateExecution and BookingsManagement.QuickAddMeetingExecution
  # (both submit the same reused create-event dialog).
  # ---------------------------------------------------------------------------

  @doc """
  Parses an ISO-8601 date string, translating the error for display.
  """
  @spec parse_date(String.t()) :: {:ok, Date.t()} | {:error, String.t()}
  def parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, dgettext("dashboard_calendar_events", "Invalid date")}
    end
  end

  @doc """
  Same as `to_utc/4`, translating the error for display.
  """
  @spec to_utc_or_error(Date.t(), non_neg_integer(), non_neg_integer(), String.t()) ::
          {:ok, DateTime.t()} | {:error, String.t()}
  def to_utc_or_error(date, hour, minute, timezone) do
    case to_utc(date, hour, minute, timezone) do
      {:ok, datetime} -> {:ok, datetime}
      {:error, _reason} -> {:error, dgettext("dashboard_calendar_events", "Invalid time")}
    end
  end

  @doc """
  An ad-hoc meeting may be created with no calendar integration at all; when
  one is selected it must be the user's own.
  """
  @spec authorize_optional_integration(Phoenix.LiveView.Socket.t(), integer() | nil) ::
          :ok | {:error, :unauthorized}
  def authorize_optional_integration(_socket, nil), do: :ok

  def authorize_optional_integration(socket, integration_id),
    do: EditWorkflow.assert_owns_integration(socket, integration_id)

  @doc """
  Validates the create-event dialog's event-mode title, which a new event can't
  be saved without (meeting mode checks it in `validate_meeting_fields/2`).
  """
  @spec validate_event_title(map()) :: :ok | {:error, String.t()}
  def validate_event_title(creating) do
    if String.trim(creating.title || "") == "" do
      {:error, dgettext("dashboard_calendar_events", "Event title is required")}
    else
      :ok
    end
  end

  @doc """
  Validates the create-event dialog's meeting-mode title and guest fields. The
  self-booking rule is enforced authoritatively by `Bookings.CreateAdHoc`,
  which compares against the stored organiser address — repeating it here
  buys a translated message on the form rather than a flash after the round
  trip.
  """
  @spec validate_meeting_fields(map(), String.t() | nil) :: :ok | {:error, String.t()}
  def validate_meeting_fields(creating, organizer_email) do
    guest_email = String.trim(creating.guest_email)

    cond do
      String.trim(creating.title || "") == "" ->
        {:error, dgettext("dashboard_calendar_events", "Meeting title is required")}

      String.trim(creating.guest_name) == "" ->
        {:error, dgettext("dashboard_calendar_events", "Guest name is required")}

      not valid_email?(guest_email) ->
        {:error, dgettext("dashboard_calendar_events", "A valid guest email is required")}

      same_address?(guest_email, organizer_email) ->
        {:error,
         dgettext(
           "dashboard_calendar_events",
           "You cannot add yourself as a guest. Use a different email address."
         )}

      true ->
        :ok
    end
  end

  defp same_address?(guest_email, organizer_email) when is_binary(organizer_email) do
    String.downcase(guest_email) == organizer_email |> String.trim() |> String.downcase()
  end

  defp same_address?(_guest_email, _organizer_email), do: false

  @doc """
  The flash copy for a successful event/meeting create, depending on whether
  attendees were invited.
  """
  @spec flash_for_create([map()]) :: String.t()
  def flash_for_create([]), do: dgettext("dashboard_calendar_events", "Event created.")

  def flash_for_create(_attendees),
    do: dgettext("dashboard_calendar_events", "Event created. Attendees have been invited.")

  @doc """
  Builds a `creating_event` map for the create-event dialog, filling defaults
  for any field `overrides` omits — the first connected calendar/its default
  booking calendar pre-selected, meeting mode when there's nothing to write a
  bare event to, everything else blank/empty. Shared by
  `CreateFormState.handle_show_create_form/2` (which overrides the date/time
  fields from either a grid-click's coordinates or "now") and
  `BookingsManagement.QuickAddMeeting.show_create_form/2` (which always
  overrides them with "now", having no grid to click).
  """
  @spec base_creating(Phoenix.LiveView.Socket.t(), map()) :: map()
  def base_creating(socket, overrides) do
    default_int_id = EditWorkflow.default_integration_id(socket)
    today = Date.to_iso8601(Clock.utc_today())

    defaults = %{
      date: today,
      end_date: today,
      start_hour: 9,
      start_minute: 0,
      end_hour: 10,
      end_minute: 0,
      all_day: false,
      title: "",
      # With no calendar that can be written to there is nothing a provider
      # event could go into, so the form opens straight in meeting mode. A
      # subscription counts as no calendar here: it can be read and never
      # written.
      mode: if(writable?(socket.assigns.integrations), do: :event, else: :meeting),
      guest_name: "",
      guest_email: "",
      # The note field stays hidden until the organiser asks for it.
      note_open: false,
      organizer_note: "",
      guest_emails: [],
      guest_email_input: "",
      # Which language the guests are written to. Defaults to the host's own
      # (they know whom they are inviting) and is theirs to change per meeting.
      locale: Locales.guest_default_locale(Map.get(socket.assigns, :current_user)),
      integration_id: default_int_id,
      calendar_id: EditWorkflow.default_calendar_id(socket.assigns.integrations, default_int_id),
      attendees: [],
      attendee_input: "",
      reminders: [],
      # Meeting mode's own reminders: when the app emails the guest before the
      # meeting. Kept apart from `reminders` above, which are the provider
      # alarms a plain calendar event carries and mean nothing to a booking.
      meeting_reminders: ReminderPickerState.new(),
      recurrence_rule: nil,
      video_integration_id: nil
    }

    Map.merge(defaults, overrides)
  end

  @doc """
  Refuses a change to a calendar event that a group meeting with live seats
  sits on: moving or resizing it, changing its recurrence, deleting it, or
  adding or removing its attendees.

  The organiser's provider event is a projection of the Tymeslot meeting, not
  the meeting itself. Moving it does not move the participants' seats (their
  reschedule links still point at the booked slot, and the next sync reports
  the organiser's own edit back as an external change); deleting it leaves
  everyone booked on a meeting with no calendar event; and its attendee list
  is not who holds a seat. The grid hides these controls on a locked event,
  so reaching here means the client asked anyway: this is the guard, not a
  hint.

  Deliberately re-read from the database rather than taken from the socket:
  the assigned lock set is as old as the last event load, and a seat booked
  since then must still count. Scoped to the acting organiser's meetings.
  """
  @spec check_seat_lock(Phoenix.LiveView.Socket.t(), map()) :: :ok | {:error, :group_booking}
  def check_seat_lock(socket, event) do
    if Meetings.group_booking_uid?(socket.assigns.current_user.id, Map.get(event, :uid)) do
      {:error, :group_booking}
    else
      :ok
    end
  end

  @doc """
  The socket-returning form of `flash_guard_error/2`, for callers already
  inside a continuation that has to hand a socket back.
  """
  @spec flash_guard(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def flash_guard(socket, {:error, :unauthorized}) do
    send(
      self(),
      {:flash,
       {:error,
        dgettext("dashboard_calendar_events", "You don't have permission to modify this event")}}
    )

    socket
  end

  def flash_guard(socket, {:error, :read_only}) do
    send(
      self(),
      {:flash,
       {:error,
        dgettext(
          "dashboard_calendar_events",
          "This calendar is read-only. Events on it can't be changed from %{app_name}.",
          app_name: Config.app_name()
        )}}
    )

    socket
  end

  def flash_guard(socket, {:error, :rate_limited, _message}) do
    send(
      self(),
      {:flash,
       {:warning, dgettext("dashboard_calendar_events", "Too many edits. Please wait a moment.")}}
    )

    socket
  end

  def flash_guard(socket, {:error, :group_booking}) do
    send(self(), {:flash, {:warning, seat_lock_message()}})
    socket
  end

  def flash_guard(socket, {:error, :until_before_start}) do
    send(
      self(),
      {:flash,
       {:error,
        dgettext(
          "dashboard_calendar_events",
          "The recurrence end date must be on or after the event start."
        )}}
    )

    socket
  end

  @doc """
  Why an event `check_seat_lock/2` refuses cannot be changed here: the one
  wording the refusal flash, the locked badge and the event modal share.
  """
  @spec seat_lock_message() :: String.t()
  def seat_lock_message do
    dgettext(
      "dashboard_calendar_events",
      "This is a group booking. Move it, cancel it or change who attends from the meeting instead."
    )
  end
end
