defmodule TymeslotWeb.Dashboard.CalendarGrid.VideoPicker do
  @moduledoc """
  The select an organiser picks an event's video provider from: "None" first,
  then each connected video integration.

  One component for every place the grid offers the choice — the new-event
  modal, the ad-hoc meeting form and the event detail modal — so the options
  and their order cannot drift apart between creating an event and editing
  one. Each caller supplies the event name its own handler listens for; the
  choice arrives as `video_integration_id` (empty for "None").
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :video_integrations, :list, required: true
  attr :selected_id, :any, default: nil
  attr :target, :any, required: true
  attr :phx_event, :string, required: true
  attr :id, :string, default: "video-picker"

  @spec video_picker(map()) :: Phoenix.LiveView.Rendered.t()
  def video_picker(assigns) do
    assigns =
      assign(
        assigns,
        :options,
        [
          {dgettext("dashboard_calendar_events", "None"), ""}
          | Enum.map(assigns.video_integrations, &{&1.name, to_string(&1.id)})
        ]
      )

    ~H"""
    <form id={"#{@id}-form"} phx-change={@phx_event} phx-target={@target}>
      <.input
        type="select"
        id={@id}
        name="video_integration_id"
        value={if is_nil(@selected_id), do: "", else: to_string(@selected_id)}
        options={@options}
      />
    </form>
    """
  end
end
