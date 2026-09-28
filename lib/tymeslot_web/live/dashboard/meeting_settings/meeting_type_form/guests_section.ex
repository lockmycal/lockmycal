defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.GuestsSection do
  @moduledoc """
  Stateless function component for the meeting-type form's Guests section.

  Renders the "allow guests" toggle. When enabled, invitees can add extra
  guest email addresses on the public booking form; each guest receives a
  confirmation email with an RSVP link. The toggle dispatches
  `toggle_allow_guests` back to the parent `MeetingTypeForm` (`@myself`),
  which owns the socket state and auto-save.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  attr :allow_guests, :boolean, required: true
  attr :max_guests, :integer, required: true
  attr :myself, :any, required: true

  @spec guests_section(map()) :: Phoenix.LiveView.Rendered.t()
  def guests_section(assigns) do
    ~H"""
    <section class="space-y-4">
      <div class="flex items-center gap-2">
        <.icon name="hero-user-group" class="w-5 h-5 text-primary-500" />
        <h3 class="text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
          {dgettext("dashboard_meeting_form", "Guests")}
        </h3>
      </div>

      <div class="card-glass p-4 flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext(
              "dashboard_meeting_form",
              "Let invitees add up to %{max_guests} guests to this meeting",
              max_guests: @max_guests
            )}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_meeting_form",
              "Each guest is emailed a confirmation with their own link to accept or decline. You'll see every guest's response on your dashboard."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@allow_guests}
          click_event="toggle_allow_guests"
          target={@myself}
          aria_label={dgettext("dashboard_meeting_form", "Let invitees add guests")}
        />
      </div>
    </section>
    """
  end
end
