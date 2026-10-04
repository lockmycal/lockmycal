defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.ContactSharingSection do
  @moduledoc """
  Stateless function component for the meeting-type form's contact sharing
  toggles.

  A booker signed in to their own account gets the meeting in their calendar
  and on their dashboard (`Tymeslot.Meetings.BookerCalendar`), named after the
  host. Whether it also shows the host's email address and phone number is the
  host's choice, made here and off by default; each booking keeps the choice it
  was made under (`Tymeslot.Bookings.Policy`). The toggles dispatch
  `toggle_show_email_to_bookers` / `toggle_show_phone_to_bookers` back to the
  parent `MeetingTypeForm` (`@myself`), which owns the socket state and
  auto-save.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :show_email_to_bookers, :boolean, required: true
  attr :show_phone_to_bookers, :boolean, required: true
  attr :myself, :any, required: true

  @spec contact_sharing_section(map()) :: Phoenix.LiveView.Rendered.t()
  def contact_sharing_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <div class="flex items-center gap-2">
        <.icon name="hero-identification" class="w-5 h-5 text-primary-500" />
        <h3 class="text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
          {dgettext("dashboard_meeting_form", "Your contact details")}
        </h3>
      </div>

      <div class="card-glass p-4 space-y-4">
        <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
          {dgettext(
            "dashboard_meeting_form",
            "A booker signed in to their account gets this meeting in their own calendar and dashboard, under your name. Choose what else they see."
          )}
        </p>

        <div class="flex items-center justify-between gap-4">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_meeting_form", "Show my email to signed-in bookers")}
          </p>
          <.enabled_toggle
            active={@show_email_to_bookers}
            click_event="toggle_show_email_to_bookers"
            target={@myself}
            aria_label={dgettext("dashboard_meeting_form", "Show my email to signed-in bookers")}
          />
        </div>

        <div class="flex items-center justify-between gap-4">
          <div class="min-w-0 flex-1 space-y-1">
            <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
              {dgettext("dashboard_meeting_form", "Show my phone to signed-in bookers")}
            </p>
            <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
              {dgettext("dashboard_meeting_form", "The phone number from your profile.")}
            </p>
          </div>
          <.enabled_toggle
            active={@show_phone_to_bookers}
            click_event="toggle_show_phone_to_bookers"
            target={@myself}
            aria_label={dgettext("dashboard_meeting_form", "Show my phone to signed-in bookers")}
          />
        </div>
      </div>
    </section>
    """
  end
end
