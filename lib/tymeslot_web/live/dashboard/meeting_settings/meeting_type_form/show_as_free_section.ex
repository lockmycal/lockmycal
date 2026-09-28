defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.ShowAsFreeSection do
  @moduledoc """
  Stateless function component for the meeting-type form's calendar
  availability toggle.

  Renders the "show as free" toggle. When enabled, bookings of this meeting
  type are written to the host's connected calendar as free/transparent
  (`TRANSP:TRANSPARENT` on CalDAV, `transparency=transparent` on Google,
  `showAs=free` on Outlook) so they do not block the host's availability. The
  toggle dispatches `toggle_show_as_free` back to the parent `MeetingTypeForm`
  (`@myself`), which owns the socket state and auto-save.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :show_as_free, :boolean, required: true
  attr :myself, :any, required: true

  @spec show_as_free_section(map()) :: Phoenix.LiveView.Rendered.t()
  def show_as_free_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <div class="flex items-center gap-2">
        <.icon name="hero-calendar-days" class="w-5 h-5 text-primary-500" />
        <h3 class="text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
          {dgettext("dashboard_meeting_form", "Calendar availability")}
        </h3>
      </div>

      <div class="card-glass p-4 flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_meeting_form", "Show these bookings as free on my calendar")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_meeting_form",
              "The event is still created, but marked as free time so it doesn't block other bookings or appear busy to people who can see your availability."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@show_as_free}
          click_event="toggle_show_as_free"
          target={@myself}
          aria_label={
            dgettext("dashboard_meeting_form", "Show these bookings as free on my calendar")
          }
        />
      </div>
    </section>
    """
  end
end
