defmodule TymeslotWeb.Dashboard.CalendarSettings.OwnBookingsSection do
  @moduledoc """
  The calendar settings page's "Your bookings on other pages" block: whether a
  booking the user makes on someone else's booking page while signed in is
  also written to their own default calendar
  (`Tymeslot.Meetings.BookerCalendar`).

  The booking form asks each time until the user ticks "Remember for next
  time" there; this is where that remembered answer is changed, or set back
  to asking.

  Its own LiveComponent, so `CalendarSettingsComponent` stays under the
  project's line-count budget.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Meetings.BookerCalendar
  alias TymeslotWeb.Live.Shared.Flash

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:current_user, assigns.current_user)
      |> assign_new(:choice, fn -> BookerCalendar.choice(assigns.current_user.id) end)

    {:ok, socket}
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_own_bookings_choice", %{"choice" => value}, socket) do
    choices = Map.new(BookerCalendar.choices(), &{Atom.to_string(&1), &1})

    with {:ok, choice} <- Map.fetch(choices, value),
         :ok <- BookerCalendar.remember(socket.assigns.current_user.id, choice) do
      Flash.info(dgettext("dashboard_calendar_settings", "Setting saved"))
      {:noreply, assign(socket, :choice, choice)}
    else
      _error ->
        Flash.error(dgettext("dashboard_calendar_settings", "Failed to save setting"))
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <section class="space-y-4" data-testid="own-bookings-section">
      <.subsection_header
        icon="hero-calendar"
        title={dgettext("dashboard_calendar_settings", "Your bookings on other pages")}
      />

      <div class="card-glass p-4 space-y-3">
        <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
          {dgettext(
            "dashboard_calendar_settings",
            "When you book a meeting on someone else's booking page while signed in, it can also be saved to your default calendar."
          )}
        </p>

        <.form
          for={%{}}
          as={:own_bookings}
          id="own-bookings-form"
          phx-change="set_own_bookings_choice"
          phx-target={@myself}
        >
          <.input
            type="select"
            name="choice"
            id="own-bookings-choice"
            label={dgettext("dashboard_calendar_settings", "Save to my calendar")}
            value={Atom.to_string(@choice)}
            options={[
              {dgettext("dashboard_calendar_settings", "Ask each time"), "ask"},
              {dgettext("dashboard_calendar_settings", "Always"), "always"},
              {dgettext("dashboard_calendar_settings", "Never"), "never"}
            ]}
          />
        </.form>
      </div>
    </section>
    """
  end
end
