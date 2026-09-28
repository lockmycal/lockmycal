defmodule TymeslotWeb.Dashboard.ProfileSettings.TimeFormatFormComponent do
  @moduledoc """
  Time format form component for profile settings.

  Lets the organiser choose whether times are shown on a 12-hour clock (AM/PM)
  or a 24-hour clock. Until they choose, their language sets the clock, so this
  starts out showing whichever format they are already seeing.

  The choice is stored once, in `calendar_preferences.time_format`, and shared
  with the calendar's own settings modal, so the two controls can never
  disagree. It applies to the surfaces the organiser reads: their dashboard and
  the emails addressed to them. Attendees keep the clock convention of their own
  language, so the public booking page is deliberately unaffected.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.CalendarGrid
  alias Tymeslot.Utils.DateTimeUtils.TimeFormat

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # assign_new, so the parent re-rendering for an unrelated reason neither
    # re-queries nor overwrites a choice this component has just saved.
    {:ok,
     assign_new(socket, :time_format, fn ->
       CalendarGrid.get_user_time_format(
         socket.assigns.current_user.id,
         Gettext.get_locale(TymeslotWeb.Gettext)
       )
     end)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("change_time_format", %{"option" => time_format}, socket) do
    if TimeFormat.valid?(time_format) do
      save_time_format(socket, time_format)
    else
      {:noreply, socket}
    end
  end

  defp save_time_format(socket, time_format) do
    case CalendarGrid.save_preferences(socket.assigns.current_user.id, %{
           time_format: time_format
         }) do
      {:ok, _preferences} ->
        send(self(), {:time_format_updated, time_format})
        Flash.info(dgettext("dashboard_profile", "Time format updated"))
        {:noreply, assign(socket, :time_format, time_format)}

      {:error, _changeset} ->
        Flash.error(dgettext("dashboard_profile", "Failed to update time format"))
        {:noreply, socket}
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="time-format-form-container">
      <.subsection_header
        icon="hero-clock"
        title={dgettext("dashboard_profile", "Time Format")}
        class="mb-3"
      />
      <div class="input p-4">
        <div class="flex items-center justify-between gap-4">
          <span class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_profile", "Set your preferred time format")}
          </span>
          <.option_toggle
            active_value={@time_format}
            click_event="change_time_format"
            target={@myself}
            aria_label={dgettext("dashboard_profile", "Set time format")}
            options={[
              {"12h", dgettext("dashboard_profile", "12h (AM/PM)")},
              {"24h", dgettext("dashboard_profile", "24h")}
            ]}
          />
        </div>
      </div>
      <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
        {dgettext(
          "dashboard_profile",
          "Controls how times are shown on your dashboard and in the emails you receive. Your booking page follows each visitor's own language."
        )}
      </p>
    </div>
    """
  end
end
