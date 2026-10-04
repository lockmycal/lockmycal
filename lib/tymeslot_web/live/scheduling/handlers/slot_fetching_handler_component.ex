defmodule TymeslotWeb.Live.Scheduling.Handlers.SlotFetchingHandlerComponent do
  @moduledoc """
  Specialized handler for slot fetching operations in scheduling themes.

  This handler provides common slot fetching functionality that can be used across
  different themes, eliminating code duplication while maintaining theme independence.

  ## Usage

      alias TymeslotWeb.Live.Scheduling.Handlers.SlotFetchingHandlerComponent

      # In your theme's handle_info callback:
      def handle_info({:fetch_available_slots, date, duration, timezone}, socket) do
        {:ok, socket} = SlotFetchingHandlerComponent.fetch_available_slots(socket, date, duration, timezone)
        {:noreply, socket}
      end

      def handle_info({ref, {:slots, duration, result}}, socket) when is_reference(ref) do
        {:noreply, SlotFetchingHandlerComponent.finish_fetch_available_slots(socket, ref, duration, result)}
      end

  ## Available Functions

  - `fetch_available_slots/4` - Start fetching the available time slots for a given date
  - `finish_fetch_available_slots/4` - Apply the fetched slots (or the failure)
  - `maybe_reload_slots/1` - Conditionally reload slots if date is selected
  - `load_slots/2` - Load slots for a specific date
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.Availability.Offer
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias TymeslotWeb.Live.Scheduling.AvailabilityHelpers

  @doc """
  Starts fetching the available slots for a given date and timezone.

  The fetch runs in a task, like the month availability fetch
  (`AvailabilityHelpers.fetch_month_availability_async/1`): it waits on the
  organiser's calendars, which can take tens of seconds when one of them is
  slow, and the page must stay responsive meanwhile. The result arrives as a
  `{ref, {:slots, duration, result}}` message that
  `finish_fetch_available_slots/4` applies. A newer fetch replaces the one
  still in flight.

  The `duration` argument is accepted for message-contract compatibility
  with callers but is not used to select the fetch: the duration is always
  resolved from the socket via `AvailabilityHelpers.duration_minutes/1`, so
  the offered slots can't drift from the duration the domain will validate
  against.

  ## Examples

      {:ok, updated_socket} =
        SlotFetchingHandlerComponent.fetch_available_slots(socket, date, nil, "America/New_York")
  """
  @spec fetch_available_slots(
          Phoenix.LiveView.Socket.t(),
          String.t(),
          term(),
          String.t()
        ) :: {:ok, Phoenix.LiveView.Socket.t()}
  def fetch_available_slots(socket, date, _duration, timezone) do
    # `request/1` computes demo mode fresh from the socket rather than reading
    # a `:demo_mode` assign: nothing in Core ever sets one, so reading the
    # assign always resolved to `nil`, silently disabling demo detection. The
    # timezone is the one the fetch message names.
    request = %{AvailabilityHelpers.request(socket) | user_timezone: timezone}

    # Single resolver for display and submit, so the offered slots can't
    # drift from the duration the domain will validate against.
    duration_to_fetch = AvailabilityHelpers.duration_minutes(socket)

    if old_task = socket.assigns[:slots_task], do: Task.shutdown(old_task, :brutal_kill)

    {task, ref} =
      AvailabilityHelpers.run_fetch(fn ->
        {:slots, duration_to_fetch, Offer.slots_for_date(request, date, duration_to_fetch)}
      end)

    {:ok, socket |> assign(:slots_task, task) |> assign(:slots_task_ref, ref)}
  end

  @doc """
  Applies the result of a `fetch_available_slots/4` fetch, unless a newer
  fetch has replaced it in the meantime (`ref` is no longer the current one).

  On success the slots are assigned and the loading state cleared; on failure
  the grid is emptied and a generic retry message is shown.
  """
  @spec finish_fetch_available_slots(
          Phoenix.LiveView.Socket.t(),
          reference(),
          pos_integer(),
          {:ok, list()} | {:error, term()}
        ) :: Phoenix.LiveView.Socket.t()
  def finish_fetch_available_slots(socket, ref, duration_to_fetch, result) do
    Process.demonitor(ref, [:flush])

    if ref == socket.assigns[:slots_task_ref] do
      socket
      |> assign(:slots_task, nil)
      |> assign(:slots_task_ref, nil)
      |> apply_slots_result(duration_to_fetch, result)
    else
      socket
    end
  end

  # `:expanded_hour` is deliberately left untouched here. Resetting it on
  # every fetch would spring a deliberately collapsed `:none` back open on
  # a refetch the booker did not ask for (a timezone change, a lost-slot
  # retry): those refetch the *same* date, and it has nothing to do with the
  # booker's previous hour selection. An explicit date pick — the one case that
  # must reset it, since the open hour would describe a grid that no longer
  # applies — resets it at the point the booker makes that choice, in
  # `handle_schedule_date_selection/2`.
  defp apply_slots_result(socket, duration_to_fetch, {:ok, slots}) do
    socket
    |> assign(:available_slots, slots)
    |> assign(:slot_interval_minutes, AvailabilityHelpers.slot_interval_minutes(socket))
    |> assign(:duration_minutes, duration_to_fetch)
    |> assign(:loading_slots, false)
    |> assign(:calendar_error, nil)
  end

  defp apply_slots_result(socket, duration_to_fetch, {:error, reason}) do
    require Logger
    Logger.error("Failed to fetch available slots", reason: LogFormat.reason(reason))

    socket
    |> assign(:available_slots, [])
    |> assign(:slot_interval_minutes, AvailabilityHelpers.slot_interval_minutes(socket))
    |> assign(:duration_minutes, duration_to_fetch)
    |> assign(:loading_slots, false)
    # Deliberately says nothing about *why*. This is the most
    # conversion-critical screen in the product, and a booker who has
    # never heard of a calendar provider can act on "try again" but
    # not on a parser. The reason is in the log line above, where the
    # person who can act on it will look.
    |> assign(
      :calendar_error,
      dgettext("booking", "No time slots could be loaded. Please try again.")
    )
  end

  @doc """
  Conditionally reloads slots if a date is currently selected.

  This function checks if there's a selected date and triggers slot reloading
  if necessary. Useful after timezone changes or other state updates.

  ## Examples

      {:ok, socket} = SlotFetchingHandlerComponent.maybe_reload_slots(socket)
  """
  @spec maybe_reload_slots(Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def maybe_reload_slots(socket) do
    case socket.assigns[:selected_date] do
      nil ->
        {:ok, socket}

      selected_date ->
        duration = socket.assigns[:duration] || socket.assigns[:selected_duration]
        timezone = socket.assigns[:user_timezone]

        socket =
          socket
          |> assign(:loading_slots, true)
          |> assign(:calendar_error, nil)
          |> tap(fn _client ->
            send(self(), {:fetch_available_slots, selected_date, duration, timezone})
          end)

        {:ok, socket}
    end
  end

  @doc """
  Loads slots for a specific date.

  This is a convenience function that sends a message to trigger slot fetching.

  ## Examples

      SlotFetchingHandlerComponent.load_slots(socket, "2024-01-15")
  """
  @spec load_slots(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()}
  def load_slots(socket, date) do
    duration = socket.assigns[:duration] || socket.assigns[:selected_duration]
    timezone = socket.assigns[:user_timezone]

    send(self(), {:fetch_available_slots, date, duration, timezone})

    socket =
      socket
      |> assign(:loading_slots, true)
      |> assign(:calendar_error, nil)

    {:ok, socket}
  end
end
