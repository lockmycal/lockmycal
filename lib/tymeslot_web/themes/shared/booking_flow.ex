defmodule TymeslotWeb.Themes.Shared.BookingFlow do
  @moduledoc """
  Shared booking orchestration for all scheduling themes.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Phoenix.Component
  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Security.InputProcessor
  alias TymeslotWeb.Live.Scheduling.BookingConfig
  alias TymeslotWeb.Live.Scheduling.Handlers.BookingSubmissionHandlerComponent
  alias TymeslotWeb.Live.Scheduling.OrganizerHelpers
  alias TymeslotWeb.Themes.Shared.BookingLocation

  @type transition_fun :: (Phoenix.LiveView.Socket.t(), atom(), map() ->
                             Phoenix.LiveView.Socket.t())

  @doc """
  Handles booking submission from the LiveView.
  This centralizes the validation and submission logic by delegating to
  the shared BookingSubmissionHandlerComponent.

  When the meeting type requires payment, the handler returns a socket that
  is already configured to redirect to the Stripe Checkout URL — we forward
  that socket without transitioning to the confirmation step so the
  attendee leaves the booking flow for the hosted payment page.

  When the booker is embedded inside an iframe (Stripe Checkout cannot
  render in an iframe), the handler instead instructs the browser to open
  Checkout in a new tab and we transition to the local `:awaiting_payment`
  view; the LiveView subscribes to `meeting_payment:<id>` and flips back
  to `:confirmation` on `:paid` or `:booking` on `:expired`.
  """
  @spec submit_booking(Phoenix.LiveView.Socket.t(), map(), transition_fun()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def submit_booking(socket, booking_params, transition_fun) do
    if socket.assigns[:submitting] do
      {:noreply, socket}
    else
      case BookingLocation.validate(socket) do
        {:ok, socket} ->
          dispatch_booking(socket, booking_params, transition_fun)

        # The chosen location asks the booker for something they have not
        # given yet (a phone number to call them on). Surfaced inline on the
        # picker rather than as a flash, and never dispatched, so no meeting
        # is created half-addressed.
        {:error, socket} ->
          {:noreply, socket |> discard_attachments() |> assign(:submitting, false)}
      end
    end
  end

  @doc """
  Takes over the files the booking component just stored for the submission
  that follows (see `TymeslotWeb.Themes.Shared.AttendeeAttachmentUpload`).
  While a submission is already in flight the new batch is not needed: it is
  deleted rather than silently replacing the files that submission carries.
  """
  @spec put_attachments(Phoenix.LiveView.Socket.t(), [map()]) :: Phoenix.LiveView.Socket.t()
  def put_attachments(socket, attachments) do
    if socket.assigns[:submitting] do
      AttendeeAttachments.delete_batch(attachments)
      socket
    else
      assign(socket, :attendee_attachments, attachments)
    end
  end

  defp dispatch_booking(socket, booking_params, transition_fun) do
    socket = assign(socket, :submitting, true)

    case BookingSubmissionHandlerComponent.submit_booking(socket, booking_params) do
      {:ok, socket} ->
        {:noreply, socket |> keep_attachments() |> transition_fun.(:confirmation, %{})}

      {:redirect, socket} ->
        {:noreply, keep_attachments(socket)}

      {:awaiting_payment, socket} ->
        {:noreply, socket |> keep_attachments() |> transition_fun.(:awaiting_payment, %{})}

      {:slot_taken, socket} ->
        {:noreply,
         socket |> discard_attachments() |> return_to_schedule_for_new_slot(transition_fun)}

      {:honeypot, socket} ->
        {:noreply,
         socket
         |> discard_attachments()
         |> put_flash(
           :info,
           dgettext(
             "booking",
             "Booking submitted successfully! You'll receive a confirmation email shortly."
           )
         )}

      {:error, socket} ->
        {:noreply, socket |> discard_attachments() |> assign(:submitting, false)}
    end
  end

  # The meeting now references the files; they stay listed on the
  # confirmation step but must not ride along into another booking made from
  # this page.
  defp keep_attachments(socket) do
    socket
    |> assign(:submitted_attachments, socket.assigns[:attendee_attachments] || [])
    |> assign(:attendee_attachments, [])
  end

  # No meeting was created, so nothing will ever reference the stored files.
  defp discard_attachments(socket) do
    AttendeeAttachments.delete_batch(socket.assigns[:attendee_attachments] || [])
    assign(socket, :attendee_attachments, [])
  end

  # Recover from a lost slot race: drop the stale time, return to the schedule
  # step (which refreshes month availability), and reload that day's slots so
  # the just-taken time disappears and the booker can immediately pick another.
  # The error flash was already set by the submission handler.
  defp return_to_schedule_for_new_slot(socket, transition_fun) do
    socket =
      socket
      |> assign(:submitting, false)
      |> assign(:selected_time, nil)
      |> assign(:available_slots, [])
      |> transition_fun.(:schedule, %{})

    case socket.assigns[:selected_date] do
      nil ->
        socket

      date ->
        send(self(), {:load_slots, date})
        assign(socket, :loading_slots, true)
    end
  end

  @spec handle_form_validation(Phoenix.LiveView.Socket.t(), map()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_form_validation(socket, booking_params) do
    # Show validation errors only after the user has interacted with the form.
    # `touched_fields` is populated by the field_blur event handler; `_target`
    # is a fallback for phx-change events that include it in the params.
    touched_fields = socket.assigns[:touched_fields] || MapSet.new()

    form_touched =
      socket.assigns[:form_touched] ||
        MapSet.size(touched_fields) > 0 ||
        Map.has_key?(booking_params, "_target")

    socket =
      socket
      |> assign(:form, Component.to_form(booking_params))
      |> assign(:validation_errors, visible_errors(booking_params, touched_fields))
      |> assign(:form_touched, form_touched)

    {:noreply, socket}
  end

  @doc """
  Marks a booking field as touched when the booker leaves it, and shows its
  error right away.

  Without re-validating here, a field left empty would show nothing until
  the next change event, which never comes when the booker only tabs
  through: they would face a disabled submit button with no hint why.
  """
  @spec handle_field_blur(Phoenix.LiveView.Socket.t(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def handle_field_blur(socket, field_name) do
    socket = OrganizerHelpers.mark_field_touched(socket, field_name)

    params =
      case socket.assigns[:form] do
        %{source: source} when is_map(source) -> source
        _no_form -> %{}
      end

    socket
    |> assign(:validation_errors, visible_errors(params, socket.assigns.touched_fields))
    |> assign(:form_touched, true)
  end

  # Filter errors to only show for fields the user has actually interacted
  # with (blurred). This matches the per-field validation UX of auth and
  # contact forms — touching name doesn't reveal email errors.
  defp visible_errors(booking_params, touched_fields) do
    case InputProcessor.validate_form(booking_params, BookingConfig.booking_field_spec()) do
      {:ok, _sanitized_params} -> %{}
      {:error, errors} -> filter_errors_for_touched_fields(errors, touched_fields)
    end
  end

  defp filter_errors_for_touched_fields(errors, touched_fields) do
    Map.filter(errors, fn {field, _msg} ->
      MapSet.member?(touched_fields, Atom.to_string(field))
    end)
  end
end
