defmodule TymeslotWeb.Components.Dashboard.Integrations.Calendar.DefaultCalendarModal do
  @moduledoc """
  Makes a calendar connection the user's default calendar
  (`Tymeslot.Integrations.Calendar.set_default_integration/3`).

  A connection with a single calendar that can take a booking becomes the
  default straight away. One with several asks which of them first, since the
  default is a calendar, not a whole account: it is where the user's copies
  of bookings they make on other pages go (`Tymeslot.Meetings.BookerCalendar`).
  The same dialog changes that calendar on the connection that already is
  the default.
  """

  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Tymeslot.Integrations.Calendar
  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Dashboard.CalendarSettingsComponent
  alias TymeslotWeb.Live.Shared.Flash

  # Must match `ComponentDispatch.component_id(:calendar_integration)` — the id
  # `CalendarSettingsComponent` is mounted under as the dashboard's `:calendar_integration` action.
  @parent_component_id "calendar_integration"

  @impl Phoenix.LiveComponent
  def mount(socket), do: {:ok, hide(socket)}

  @impl Phoenix.LiveComponent
  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl Phoenix.LiveComponent
  def handle_event("show", %{"id" => id}, socket) do
    with {int_id, ""} <- Integer.parse(id),
         {:ok, integration} <- Calendar.get_integration(int_id, socket.assigns.current_user.id) do
      case Calendar.writable_calendars(integration.calendar_list) do
        [_one_or_none | []] -> set_default(socket, integration, nil)
        [] -> set_default(socket, integration, nil)
        choices -> {:noreply, open(socket, integration, choices)}
      end
    else
      _not_found ->
        Flash.error(dgettext("dashboard_calendar_settings", "Integration not found"))
        {:noreply, socket}
    end
  end

  def handle_event("hide", _params, socket), do: {:noreply, hide(socket)}

  def handle_event("save", %{"calendar_id" => calendar_id}, socket) do
    case socket.assigns.integration do
      nil -> {:noreply, hide(socket)}
      integration -> set_default(socket, integration, calendar_id)
    end
  end

  defp set_default(socket, integration, calendar_id) do
    user_id = socket.assigns.current_user.id

    case Calendar.set_default_integration(user_id, integration.id, calendar_id) do
      {:ok, _integration} ->
        Flash.info(dgettext("dashboard_calendar_settings", "Default calendar updated"))
        send(self(), {:integration_updated, :calendar})
        send_update(CalendarSettingsComponent, id: @parent_component_id)
        {:noreply, hide(socket)}

      {:error, _reason} ->
        Flash.error(dgettext("dashboard_calendar_settings", "This calendar cannot take bookings"))
        {:noreply, socket}
    end
  end

  # Preselects the calendar now taking the copies: the one picked before, on
  # the connection that is already the default, else the connection's own
  # booking calendar.
  defp open(socket, integration, choices) do
    current =
      picked_calendar(integration, choices) ||
        Calendar.default_booking_calendar(choices, integration.default_booking_calendar_id)

    socket
    |> assign(:show, true)
    |> assign(:integration, integration)
    |> assign(:choices, choices)
    |> assign(:current_id, current && current.id)
  end

  defp picked_calendar(%{id: integration_id, user_id: user_id}, choices) do
    case Calendar.default_calendar(user_id) do
      {^integration_id, calendar_id} when is_binary(calendar_id) ->
        Enum.find(choices, &(&1.id == calendar_id))

      _no_pick ->
        nil
    end
  end

  defp hide(socket) do
    socket
    |> assign(:show, false)
    |> assign(:integration, nil)
    |> assign(:choices, [])
    |> assign(:current_id, nil)
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <CoreComponents.modal
        id={"#{@id}-dialog"}
        show={@show}
        on_cancel={JS.push("hide", target: @myself)}
        size={:small}
      >
        <:header>
          {dgettext("dashboard_calendar_settings", "Choose your default calendar")}
        </:header>
        <.form
          :if={@integration}
          for={%{}}
          id="default-calendar-form"
          phx-submit="save"
          phx-target={@myself}
          class="space-y-6"
        >
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_calendar_settings",
              "%{account} has several calendars. Your bookings on other pages are saved to the one you choose.",
              account: @integration.name
            )}
          </p>
          <.input
            type="select"
            name="calendar_id"
            id="default-calendar-choice"
            label={dgettext("dashboard_calendar_settings", "Default calendar")}
            value={@current_id}
            options={Enum.map(@choices, &{&1.name || &1.id, &1.id})}
          />
          <div class="flex justify-end gap-3">
            <CoreComponents.action_button
              variant={:secondary}
              phx-click={JS.push("hide", target: @myself)}
            >
              {dgettext("dashboard_calendar_settings", "Cancel")}
            </CoreComponents.action_button>
            <CoreComponents.action_button type="submit">
              {dgettext("dashboard_calendar_settings", "Set as default")}
            </CoreComponents.action_button>
          </div>
        </.form>
      </CoreComponents.modal>
    </div>
    """
  end
end
