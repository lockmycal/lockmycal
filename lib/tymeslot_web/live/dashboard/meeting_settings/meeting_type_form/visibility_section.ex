defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.VisibilitySection do
  @moduledoc """
  Stateless function component for the meeting-type form's Visibility section.

  Renders the "hide from public booking page" switch for an existing meeting
  type (edit mode only — a type must exist before it can be hidden). Unlike
  the other sections, the toggle dispatches `toggle_private` to the parent
  `ServiceSettingsComponent` (`@parent`), which owns persistence of the flag
  and refreshes the meeting type list.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :type, :map, required: true
  attr :parent, :any, required: true

  @spec visibility_section(map()) :: Phoenix.LiveView.Rendered.t()
  def visibility_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <div class="flex items-center gap-2">
        <.icon name="hero-eye-slash" class="w-5 h-5 text-primary-500" />
        <h3 class="text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
          {dgettext("dashboard_meeting_form", "Visibility")}
        </h3>
      </div>

      <div class="card-glass flex items-center justify-between gap-4 p-4">
        <div class="space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_meeting_form", "Hide from public booking page")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_meeting_form",
              "When on, this meeting type is reachable only through its direct link."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@type.is_private}
          click_event="toggle_private"
          target={@parent}
          aria_label={dgettext("dashboard_meeting_form", "Hide from public booking page")}
        />
      </div>
    </section>
    """
  end
end
