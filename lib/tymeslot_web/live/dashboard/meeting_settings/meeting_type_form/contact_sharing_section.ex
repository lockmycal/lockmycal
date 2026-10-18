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
      <.subsection_header
        icon="hero-identification"
        title={dgettext("dashboard_meeting_form", "Your contact details")}
        description={
          dgettext(
            "dashboard_meeting_form",
            "A booker signed in to their account gets this meeting in their own calendar and dashboard, under your name. Choose what else they see."
          )
        }
      />

      <.setting_row
        id="show-email-to-bookers-toggle"
        control={:switch}
        label={dgettext("dashboard_meeting_form", "Show my email to signed-in bookers")}
        checked={@show_email_to_bookers}
        phx-value-state={to_string(!@show_email_to_bookers)}
        on_change="toggle_show_email_to_bookers"
        target={@myself}
      />

      <.setting_row
        id="show-phone-to-bookers-toggle"
        control={:switch}
        label={dgettext("dashboard_meeting_form", "Show my phone to signed-in bookers")}
        description={dgettext("dashboard_meeting_form", "The phone number from your profile.")}
        checked={@show_phone_to_bookers}
        phx-value-state={to_string(!@show_phone_to_bookers)}
        on_change="toggle_show_phone_to_bookers"
        target={@myself}
      />
    </section>
    """
  end
end
