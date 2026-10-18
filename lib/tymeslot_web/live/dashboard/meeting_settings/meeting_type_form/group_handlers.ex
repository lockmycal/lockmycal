defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.GroupHandlers do
  @moduledoc """
  Event-handling logic for the meeting-type form's Group bookings section.

  Extracted from `MeetingTypeForm` to keep that module under the large-module
  line limit. `MeetingTypeForm.handle_event/3` delegates the section's events
  here (`handle_event/3`), each returning the updated socket (auto-saving
  where the change is persistable).
  """

  alias Tymeslot.MeetingTypes.InputValidation
  alias Tymeslot.Validation.Constraints
  alias TymeslotWeb.Dashboard.MeetingSettings.Helpers
  alias TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.{Autosave, GroupRules, Init}
  alias TymeslotWeb.Live.Shared.FormValidationHelpers

  import Phoenix.Component, only: [assign: 3]

  @doc "Dispatches one of the Group bookings section's events."
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_event("toggle_group_bookings", params, socket),
    do: toggle_group_bookings(params, socket)

  def handle_event(
        "change_max_participants",
        %{"meeting_type" => %{"max_participants_input" => value}},
        socket
      ),
      do: change_max_participants(value, socket)

  def handle_event("change_registration_mode", %{"option" => mode}, socket)
      when mode in ["open", "invite_only"] do
    socket
    |> assign(:registration_mode, mode)
    |> assign(
      :form_errors,
      FormValidationHelpers.delete_field_error(socket.assigns.form_errors, :invited_emails)
    )
    |> Autosave.maybe_run()
  end

  def handle_event(
        "change_invited_emails",
        %{"meeting_type" => %{"invited_emails_input" => value}},
        socket
      ) do
    socket
    |> assign(:invited_emails_input, value)
    |> assign(
      :form_errors,
      FormValidationHelpers.delete_field_error(socket.assigns.form_errors, :invited_emails)
    )
    |> Autosave.maybe_run()
  end

  def handle_event("toggle_seat_availability", params, socket) do
    socket
    |> assign(
      :show_seat_availability,
      requested_state(params, socket.assigns.show_seat_availability)
    )
    |> Autosave.maybe_run()
  end

  def handle_event("toggle_last_spots", params, socket) do
    threshold =
      if requested_state(params, socket.assigns.last_spots_threshold != nil),
        do: socket.assigns.last_spots_threshold || Init.default_last_spots()

    socket
    |> assign(:last_spots_threshold, threshold)
    |> Autosave.maybe_run()
  end

  # The input is bounded by its own min and max, so a value outside them is
  # clamped rather than refused, and one that is not a number is ignored.
  def handle_event(
        "change_last_spots_threshold",
        %{"meeting_type" => %{"last_spots_threshold_input" => value}},
        socket
      ) do
    case Integer.parse(value) do
      {count, ""} ->
        range = Constraints.last_spots_threshold_range()

        socket
        |> assign(:last_spots_threshold, count |> max(range.first) |> min(range.last))
        |> Autosave.maybe_run()

      _not_a_number ->
        socket
    end
  end

  def handle_event(_event, _params, socket), do: socket

  @doc """
  Turns group bookings on or off. `state` is the toggle's requested value;
  an event without one (a stale or forged click) flips the current value.

  Turning them on is refused while anything stands in the way
  (`GroupRules.enable_blocker/1`: no plan access, payment or approval
  required, a location that is not fixed in advance). The control renders
  disabled with the reason, so this only stops a stale or forged event.
  Turning them off is always allowed.

  A host who has lost charge capability cannot reach the payments toggle, so
  a required payment does not block them; enabling clears `payment_required`
  instead, keeping the two mutually exclusive without a dead end.
  """
  @spec toggle_group_bookings(map(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def toggle_group_bookings(params, socket) do
    enable = requested_state(params, socket.assigns.group_bookings_enabled)

    cond do
      enable == socket.assigns.group_bookings_enabled ->
        socket

      enable and GroupRules.enable_blocker(socket.assigns) != nil ->
        socket

      true ->
        socket
        |> assign(:group_bookings_enabled, enable)
        |> assign(:payment_required, socket.assigns.payment_required and not enable)
        |> assign(
          :form_errors,
          FormValidationHelpers.delete_field_error(socket.assigns.form_errors, :max_participants)
        )
        |> Autosave.maybe_run()
    end
  end

  @doc """
  Applies a typed participant limit. A value outside the group range keeps
  the raw input on screen with an inline error and skips the auto-save, so
  the indicator must not claim the form is saved meanwhile.
  """
  @spec change_max_participants(String.t(), Phoenix.LiveView.Socket.t()) ::
          Phoenix.LiveView.Socket.t()
  def change_max_participants(value, socket) do
    metadata = Helpers.get_security_metadata(socket)

    case InputValidation.validate_field(:group_participants, value, metadata) do
      {:ok, sanitized} ->
        socket
        |> assign(:max_participants, sanitized)
        |> assign(
          :form_errors,
          FormValidationHelpers.delete_field_error(socket.assigns.form_errors, :max_participants)
        )
        |> Autosave.maybe_run()

      {:error, %{max_participants: message}} ->
        socket
        |> assign(:max_participants, value)
        |> assign(:save_status, :unsaved)
        |> assign(:form_errors, Map.put(socket.assigns.form_errors, :max_participants, message))
    end
  end

  defp requested_state(%{"state" => state}, _current), do: state == "true"
  defp requested_state(_params, current), do: not current
end
