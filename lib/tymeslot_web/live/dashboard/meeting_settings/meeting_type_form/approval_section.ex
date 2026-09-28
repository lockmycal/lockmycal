defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.ApprovalSection do
  @moduledoc """
  Stateless function component for the meeting-type form's Approval section.

  Renders the toggle that decides whether bookings on this meeting type are
  confirmed on submission or held for the host to answer, plus the window they
  have to answer in.

  The window input only appears once approval is on, because a window with no
  gate to apply to is a setting that does nothing. Both dispatch back to the
  parent `MeetingTypeForm` (`@myself`), which owns the socket state and
  auto-save.

  The copy is deliberate about what the invitee sees: a host turning this on is
  changing what their booking page promises, and the two emails are the visible
  half of that change.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Validation.Constraints

  attr :requires_approval, :boolean, required: true
  attr :approval_window_hours, :any, default: nil
  attr :errors, :list, default: []
  attr :myself, :any, required: true

  @spec approval_section(map()) :: Phoenix.LiveView.Rendered.t()
  def approval_section(assigns) do
    assigns = assign(assigns, :window_range, Constraints.approval_window_hours_range())

    ~H"""
    <section class="space-y-4">
      <div class="flex items-center gap-2">
        <.icon name="hero-inbox-arrow-down" class="w-5 h-5 text-primary-500" />
        <h3 class="text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
          {dgettext("dashboard_meeting_form", "Approval")}
        </h3>
      </div>

      <div class="card-glass p-4 flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_meeting_form", "Confirm each booking myself")}
          </p>
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {dgettext(
              "dashboard_meeting_form",
              "Invitees get a \"request received\" email instead of a confirmation, and the slot is held so nobody else can take it. They get the confirmation and the calendar invite once you accept."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@requires_approval}
          click_event="toggle_requires_approval"
          target={@myself}
          aria_label={dgettext("dashboard_meeting_form", "Confirm each booking myself")}
        />
      </div>

      <div :if={@requires_approval} class="card-glass p-4 space-y-2">
        <label class="label" for="approval-window-hours">
          {dgettext("dashboard_meeting_form", "Answer within")}
        </label>

        <div class="flex items-center gap-3">
          <input
            type="number"
            id="approval-window-hours"
            name="meeting_type[approval_window_hours]"
            class="input w-32"
            value={@approval_window_hours}
            min={@window_range.first}
            max={@window_range.last}
            step="1"
            placeholder={Constraints.default_approval_window_hours()}
            phx-change="update_approval_window"
            phx-debounce="500"
            phx-target={@myself}
            data-testid="approval-window-hours"
          />
          <span class="text-token-sm text-neutral-600 dark:text-neutral-300">
            {dngettext(
              "dashboard_meeting_form",
              "hour",
              "hours",
              @approval_window_hours || Constraints.default_approval_window_hours()
            )}
          </span>
        </div>

        <p :for={error <- @errors} class="text-token-sm text-red-600">{error}</p>

        <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
          {dgettext(
            "dashboard_meeting_form",
            "If you don't answer in time the request lapses, the slot is released, and the invitee is told. Silence never confirms a booking. Leave blank to use %{default} hours.",
            default: Constraints.default_approval_window_hours()
          )}
        </p>
      </div>
    </section>
    """
  end
end
