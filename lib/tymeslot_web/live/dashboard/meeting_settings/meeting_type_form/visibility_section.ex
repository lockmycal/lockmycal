defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.VisibilitySection do
  @moduledoc """
  Stateless function component for the meeting-type form's Visibility section.

  Renders the "hide from public booking page" and "show in embedded widget"
  switches for an existing meeting type (edit mode only — a type must exist
  before its visibility can change). Unlike the other sections, the toggles
  dispatch `toggle_private` / `toggle_show_in_embed` to the parent
  `ServiceSettingsComponent` (`@parent`), which owns persistence of the flags
  and refreshes the meeting type list. The two flags are independent; see
  `Tymeslot.MeetingTypes.Visibility`.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :type, :map, required: true
  attr :parent, :any, required: true

  @spec visibility_section(map()) :: Phoenix.LiveView.Rendered.t()
  def visibility_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <.subsection_header
        icon="hero-eye-slash"
        title={dgettext("dashboard_meeting_form", "Visibility")}
      />

      <.setting_row
        id={"meeting-type-private-toggle-#{@type.id}"}
        control={:switch}
        label={dgettext("dashboard_meeting_form", "Hide from public booking page")}
        description={
          dgettext(
            "dashboard_meeting_form",
            "When on, this meeting type is reachable only through its direct link."
          )
        }
        checked={@type.is_private == true}
        phx-value-state={to_string(!@type.is_private)}
        on_change="toggle_private"
        target={@parent}
        phx-value-id={@type.id}
      />

      <.setting_row
        id={"meeting-type-embed-toggle-#{@type.id}"}
        control={:switch}
        label={dgettext("dashboard_meeting_form", "Show in embedded widget")}
        description={
          dgettext(
            "dashboard_meeting_form",
            "When on, this meeting type is listed in the booking widget embedded on your website. Independent of the public booking page."
          )
        }
        checked={@type.show_in_embed == true}
        phx-value-state={to_string(!@type.show_in_embed)}
        on_change="toggle_show_in_embed"
        target={@parent}
        phx-value-id={@type.id}
      />
    </section>
    """
  end
end
