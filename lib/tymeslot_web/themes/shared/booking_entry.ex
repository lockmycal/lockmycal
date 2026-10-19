defmodule TymeslotWeb.Themes.Shared.BookingEntry do
  @moduledoc """
  The fork's part of entering the booking step, which
  `LiveHelpers.StepEntry.handle_booking_entry/2` runs after setting up the
  booking form: for a signed-in booker, the offer of a copy in their own
  calendar, and for a signed-out one, the way to sign in and come back for it.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Tymeslot.Meetings.BookerCalendar
  alias TymeslotWeb.Themes.Shared.PathHandlers

  @doc "Assigns `:own_calendar_offer` and `:own_calendar_login_path`."
  @spec assign_own_calendar(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def assign_own_calendar(socket) do
    socket
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
