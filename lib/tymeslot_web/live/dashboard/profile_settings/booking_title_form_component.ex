defmodule TymeslotWeb.Dashboard.ProfileSettings.BookingTitleFormComponent do
  @moduledoc """
  Booking title form component for profile settings.

  Lets the organiser choose what names a booking on their dashboard agenda and
  calendar: the "Meeting Information" the guest entered when booking, or the
  meeting type's title. A booking without meeting information always falls
  back to the meeting type's title (see `Tymeslot.Meetings.DisplayTitle`).

  Stored in `calendar_preferences.booking_title_source`, alongside the other
  dashboard display preferences such as the time format.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.CalendarGrid
  alias Tymeslot.Meetings.DisplayTitle

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # assign_new, so the parent re-rendering for an unrelated reason neither
    # re-queries nor overwrites a choice this component has just saved.
    {:ok,
     assign_new(socket, :booking_title_source, fn ->
       CalendarGrid.get_or_create_preferences(socket.assigns.current_user.id).booking_title_source
     end)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("change_booking_title_source", %{"option" => source}, socket) do
    if DisplayTitle.valid?(source) do
      save_booking_title_source(socket, source)
    else
      {:noreply, socket}
    end
  end

  defp save_booking_title_source(socket, source) do
    case CalendarGrid.save_preferences(socket.assigns.current_user.id, %{
           booking_title_source: source
         }) do
      {:ok, _preferences} ->
        Flash.info(dgettext("dashboard_profile", "Meeting titles updated"))
        {:noreply, assign(socket, :booking_title_source, source)}

      {:error, _changeset} ->
        Flash.error(dgettext("dashboard_profile", "Failed to update meeting titles"))
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="booking-title-form-container">
      <.subsection_header
        icon="hero-tag"
        title={dgettext("dashboard_profile", "Meeting Titles")}
        class="mb-3"
      />
      <div class="input p-4">
        <div class="flex items-center justify-between gap-4">
          <span class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_profile", "Name bookings by")}
          </span>
          <.option_toggle
            active_value={@booking_title_source}
            click_event="change_booking_title_source"
            target={@myself}
            aria_label={dgettext("dashboard_profile", "Set meeting titles")}
            options={[
              {"meeting_info", dgettext("dashboard_profile", "Meeting Information")},
              {"meeting_type", dgettext("dashboard_profile", "Meeting type")}
            ]}
          />
        </div>
      </div>
      <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
        {dgettext(
          "dashboard_profile",
          "Controls how bookings are titled on your dashboard overview and calendar and in your connected calendar: by the meeting information your guest entered when booking, or by the meeting type. Bookings without meeting information always show the meeting type. The event description in your connected calendar always carries all the details. Events already in your calendar change the next time they are updated."
        )}
      </p>
    </div>
    """
  end
end
