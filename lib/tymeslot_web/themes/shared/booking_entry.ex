defmodule TymeslotWeb.Themes.Shared.BookingEntry do
  @moduledoc """
  Entering the booking step once `LiveHelpers.handle_booking_entry/2` has the
  date/time selection (or a reschedule) and the meeting type resolved: routing
  to `:questions` while the custom questions still need the booker, then
  setting up the booking form — its prefill, submission token, client IP and,
  for a signed-in booker, the offer of a copy in their own calendar.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.Bookings.SubmissionToken
  alias Tymeslot.Meetings.BookerCalendar
  alias Tymeslot.Scheduling.ThemeFlow
  alias TymeslotWeb.Helpers.ClientIP
  alias TymeslotWeb.Live.Scheduling.OrganizerHelpers
  alias TymeslotWeb.Themes.Shared.CustomQuestions.Engine, as: QEngine
  alias TymeslotWeb.Themes.Shared.GuestBooking
  alias TymeslotWeb.Themes.Shared.PathHandlers

  @doc "Routes to `:questions` when needed and sets up the booking form."
  @spec enter(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def enter(socket) do
    socket
    |> maybe_route_to_questions()
    |> set_up_booking_form()
  end

  # `/:username/:slug/book` can be entered directly (a reschedule deep-link,
  # or a locale switch mid-flow, both of which redirect straight back to this
  # URL). Neither passes through the `:questions` step, so a meeting type with
  # required custom fields would otherwise seed the engine with definitions
  # but no answers and render the booking step, which has no UI for them —
  # every submit then fails validation with no way to correct it. Route to
  # `:questions` instead whenever the freshly-resolved engine still needs it;
  # forward navigation from there already lands back on `:booking`.
  defp maybe_route_to_questions(socket) do
    if needs_questions_step?(socket.assigns[:engine]) do
      assign(socket, :current_state, :questions)
    else
      socket
    end
  end

  # Answers a reschedule carried over are shown, never submitted unseen.
  # They validate, so the unanswered-required arm alone would skip the one
  # screen that displays them.
  defp needs_questions_step?(%QEngine{} = engine) do
    not QEngine.skipped?(engine) &&
      (QEngine.pending_review?(engine) ||
         match?({:error, _errors}, QEngine.validate_all(engine)))
  end

  defp needs_questions_step?(_engine), do: false

  defp set_up_booking_form(socket) do
    # Set up form and rate limiting
    client_ip = ClientIP.get(socket)
    submission_token = SubmissionToken.generate()

    # Pre-fill form if rescheduling, scoped to the organizer to prevent PII
    # leaks; otherwise from the signed-in visitor, then the booking link's
    # fragment, if it carried one
    form_data =
      case socket.assigns[:reschedule_seat_token] do
        nil ->
          ThemeFlow.build_booking_form_data(
            socket.assigns[:reschedule_meeting_uid],
            socket.assigns[:organizer_user_id],
            Map.merge(
              ThemeFlow.signed_in_prefill(socket.assigns[:current_user]),
              socket.assigns.attendee_prefill
            )
          )

        seat_token ->
          ThemeFlow.build_seat_booking_form_data(seat_token)
      end

    socket
    |> OrganizerHelpers.setup_form_state(form_data, as: :booking)
    |> GuestBooking.assign_seat_cap()
    |> assign(:client_ip, client_ip)
    |> assign(:submission_token, submission_token)
    |> assign(:submission_processed, false)
    |> assign(:own_calendar_offer, own_calendar_offer(socket))
    |> assign(:own_calendar_login_path, own_calendar_login_path(socket))
  end

  # A signed-out visitor can sign in and come straight back to this form with
  # the same slot, where they are then offered their own calendar copy.
  defp own_calendar_login_path(socket) do
    if is_nil(socket.assigns[:current_user]) and !socket.assigns[:is_rescheduling] do
      "/auth/login?" <> URI.encode_query(%{"return_to" => PathHandlers.booking_form_path(socket)})
    end
  end

  # A reschedule moves the copy the booker already has, if any; it is not
  # offered again.
  defp own_calendar_offer(socket) do
    case {socket.assigns[:is_rescheduling], socket.assigns[:current_user]} do
      {true, _user} ->
        nil

      {_new_booking, %{id: user_id}} ->
        BookerCalendar.offer(user_id, socket.assigns[:organizer_user_id])

      {_new_booking, _signed_out} ->
        nil
    end
  end
end
