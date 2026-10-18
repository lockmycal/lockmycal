defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.GroupBookingsSection do
  @moduledoc """
  Stateless function component for the meeting-type form's Group bookings
  section.

  Renders the "Group bookings" toggle and, when enabled, the
  participant-limit number input (2 up to the `Constraints` maximum) and
  what the booking page says about each time's spots: the traffic-light
  level (`toggle_seat_availability`) and the exact count once a time is down
  to its last few spots (`toggle_last_spots`, with the threshold posted as
  `last_spots_threshold_input` to `change_last_spots_threshold`). The rule
  they feed is `Tymeslot.Meetings.Seats.display/3`.

  A group type cannot require payment or approval, and its location has to be
  fixed in advance (`Tymeslot.MeetingTypes.GroupLocationRule`). While any of
  those stands in the way (`GroupRules.enable_blocker/1`, the `blocker`
  attr), the toggle renders disabled with a hint saying what to change; the
  parent guards the event server-side and the changeset enforces the rules.
  Turning group bookings off is never blocked. The payment rule does not
  block a host who has since lost charge capability: the payments toggle is
  unreachable in that state, so the parent clears `payment_required` as part
  of enabling group bookings instead.

  Group bookings can be a paid feature. Without access (`allowed: false`) a
  one-to-one type shows the upgrade placeholder registered under
  `:feature_placeholder_components[:group_bookings]`, the same way the
  custom-questions section does; an existing group type keeps the section, so
  its host can still save it as it is or turn group bookings off.

  The toggle and input dispatch `toggle_group_bookings` and
  `change_max_participants` back to the parent `MeetingTypeForm`
  (`@myself`), which owns the socket state and auto-save
  (`MeetingTypeForm.GroupHandlers`). The visible input
  posts as `max_participants_input`; the canonical `max_participants` param
  is serialised from socket state by `Submission.build_params/1`, mirroring
  the payments section's `price_input`/`price` split.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Utils.FormHelpers
  alias Tymeslot.Validation.Constraints
  alias TymeslotWeb.Dashboard.MeetingSettings.Helpers
  alias TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.GroupRules
  alias TymeslotWeb.Live.Shared.FormValidationHelpers

  attr :group_bookings_enabled, :boolean, required: true
  attr :max_participants, :string, required: true
  attr :registration_mode, :string, default: "open"
  attr :invited_emails_input, :string, default: ""
  attr :show_seat_availability, :boolean, default: true
  attr :last_spots_threshold, :integer, default: nil
  attr :payment_required, :boolean, required: true
  attr :blocker, :any, default: nil, doc: "`GroupRules.enable_blocker/1`'s answer"
  attr :allowed, :boolean, default: true
  attr :form_id, :string, required: true
  attr :current_user, :any, default: nil
  attr :form_errors, :map, required: true
  attr :myself, :any, required: true

  @spec group_bookings_section(map()) :: Phoenix.LiveView.Rendered.t()
  def group_bookings_section(%{allowed: false, group_bookings_enabled: false} = assigns) do
    assigns = assign(assigns, :placeholder_component, placeholder_component())

    ~H"""
    <section data-testid="group-bookings-locked">
      <%= if @placeholder_component do %>
        <.live_component
          module={@placeholder_component}
          id={"group-bookings-upgrade-#{@form_id}"}
          feature={:group_bookings}
          current_user={@current_user}
        />
      <% else %>
        <%!-- No placeholder registered: a minimal notice rather than nothing,
              so a misconfiguration is noticed. --%>
        <.card class="text-center">
          <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
            {FormHelpers.group_bookings_not_allowed_message()}
          </p>
        </.card>
      <% end %>
    </section>
    """
  end

  def group_bookings_section(assigns) do
    assigns =
      assign(
        assigns,
        :toggle_disabled,
        not assigns.group_bookings_enabled and assigns.blocker != nil
      )

    ~H"""
    <section class="space-y-4" data-testid="group-bookings-section">
      <.subsection_header
        icon="hero-users"
        title={dgettext("dashboard_meeting_form", "Group bookings")}
      />

      <.setting_row
        id={"group-bookings-toggle-#{@form_id}"}
        control={:switch}
        label={dgettext("dashboard_meeting_form", "Let multiple people book the same time slot")}
        description={
          dgettext(
            "dashboard_meeting_form",
            "Each slot stays open until the participant limit is reached, and everyone booked into it meets together."
          )
        }
        checked={@group_bookings_enabled}
        phx-value-state={to_string(!@group_bookings_enabled)}
        disabled={@toggle_disabled}
        on_change="toggle_group_bookings"
        target={@myself}
      >
        <:disabled_reason>
          <span data-testid="group-bookings-blocker">{blocker_message(@blocker)}</span>
        </:disabled_reason>
      </.setting_row>

      <div :if={@group_bookings_enabled and not @payment_required} class="max-w-xs">
        <.input
          type="number"
          name="meeting_type[max_participants_input]"
          label={dgettext("dashboard_meeting_form", "Participant limit")}
          value={@max_participants}
          min={Constraints.group_participants_range().first}
          max={Constraints.group_participants_range().last}
          step="1"
          phx-change="change_max_participants"
          phx-debounce="500"
          phx-target={@myself}
          errors={
            FormValidationHelpers.field_errors(@form_errors, :max_participants)
            |> Enum.map(&Helpers.format_errors/1)
          }
        />
        <p class="mt-1 text-token-sm text-neutral-600 dark:text-neutral-300">
          {dgettext("dashboard_meeting_form", "Between %{min} and %{max} participants per slot.",
            min: Constraints.group_participants_range().first,
            max: Constraints.group_participants_range().last
          )}
        </p>
      </div>

      <.card
        :if={@group_bookings_enabled}
        variant={:flat}
        padding={:sm}
        class="space-y-3"
        data-testid="group-registration"
      >
        <div class="flex items-center justify-between gap-4 flex-wrap">
          <div class="min-w-0 flex-1 space-y-1">
            <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
              {dgettext("dashboard_meeting_form", "Who can book")}
            </p>
            <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
              {dgettext(
                "dashboard_meeting_form",
                "With invitation only, just the addresses below can book a spot, each for themselves (no guests). Changes apply to new bookings; spots already booked stay."
              )}
            </p>
          </div>
          <.option_toggle
            options={[
              {"open", dgettext("dashboard_meeting_form", "Anyone")},
              {"invite_only", dgettext("dashboard_meeting_form", "Invitation only")}
            ]}
            active_value={@registration_mode}
            click_event="change_registration_mode"
            target={@myself}
            aria_label={dgettext("dashboard_meeting_form", "Who can book")}
          />
        </div>

        <div :if={@registration_mode == "invite_only"}>
          <.input
            type="textarea"
            id={"invited-emails-#{@form_id}"}
            name="meeting_type[invited_emails_input]"
            label={dgettext("dashboard_meeting_form", "Invited email addresses")}
            value={@invited_emails_input}
            rows={6}
            placeholder="anna@example.com\npetr@example.com"
            phx-change="change_invited_emails"
            phx-debounce="800"
            phx-target={@myself}
            errors={
              FormValidationHelpers.field_errors(@form_errors, :invited_emails)
              |> Enum.map(&Helpers.format_errors/1)
            }
          />
          <p class="mt-1 text-token-sm text-neutral-600 dark:text-neutral-300">
            {dgettext(
              "dashboard_meeting_form",
              "One address per line, or separated by commas. Up to %{max} addresses.",
              max: Constraints.max_invited_emails()
            )}
          </p>
        </div>
      </.card>

      <div
        :if={@group_bookings_enabled and not @payment_required}
        class="space-y-4"
        data-testid="seat-display-settings"
      >
        <.setting_row
          id={"seat-availability-toggle-#{@form_id}"}
          label={dgettext("dashboard_meeting_form", "Show how full each time is")}
          description={
            dgettext(
              "dashboard_meeting_form",
              "Times are marked green, amber or red, labelled \"Plenty left\", \"Filling up\" or \"Almost full\"."
            )
          }
          control={:switch}
          checked={@show_seat_availability}
          phx-value-state={to_string(!@show_seat_availability)}
          on_change="toggle_seat_availability"
          target={@myself}
        />

        <.setting_row
          id={"last-spots-toggle-#{@form_id}"}
          label={dgettext("dashboard_meeting_form", "Show the count for the last spots")}
          description={
            dgettext(
              "dashboard_meeting_form",
              "A time shows how many spots are left, such as \"3 spots left\", only once it is down to its last few."
            )
          }
          control={:switch}
          checked={@last_spots_threshold != nil}
          phx-value-state={to_string(is_nil(@last_spots_threshold))}
          on_change="toggle_last_spots"
          target={@myself}
        />

        <div :if={@last_spots_threshold}>
          <div class="max-w-xs">
            <.input
              type="number"
              name="meeting_type[last_spots_threshold_input]"
              label={dgettext("dashboard_meeting_form", "Last spots")}
              value={@last_spots_threshold}
              min={Constraints.last_spots_threshold_range().first}
              max={Constraints.last_spots_threshold_range().last}
              step="1"
              phx-change="change_last_spots_threshold"
              phx-debounce="500"
              phx-target={@myself}
              errors={
                FormValidationHelpers.field_errors(@form_errors, :last_spots_threshold)
                |> Enum.map(&Helpers.format_errors/1)
              }
            />
          </div>
          <p class="mt-1 text-token-sm text-neutral-600 dark:text-neutral-300">
            {dngettext(
              "dashboard_meeting_form",
              "The count appears once %{count} spot or fewer is left.",
              "The count appears once %{count} spots or fewer are left.",
              @last_spots_threshold,
              count: @last_spots_threshold
            )}
          </p>
        </div>
      </div>

      <%!-- The number input above only renders while the toggle is on and
           payment is not required. A cross-field error can still land on
           this same field while it's hidden, such as the changeset's mutual
           exclusion check on `:max_participants` when payment becomes
           required, so mirror the payments section's unconditional error
           outlet rather than let it go silently invisible. --%>
      <%= if not (@group_bookings_enabled and not @payment_required) do %>
        <%= for error <- FormValidationHelpers.field_errors(@form_errors, :max_participants) do %>
          <p class="form-error">{Helpers.format_errors(error)}</p>
        <% end %>
      <% end %>
    </section>
    """
  end

  defp blocker_message(:plan), do: FormHelpers.group_bookings_not_allowed_message()

  defp blocker_message(:payment),
    do: dgettext("dashboard_meeting_form", "Turn off payments to enable group bookings.")

  defp blocker_message(:approval),
    do: dgettext("dashboard_meeting_form", "Turn off approval to enable group bookings.")

  defp blocker_message({:location, reason}), do: GroupRules.location_message(reason)

  # Bracket access works for both a keyword list and a map. Core leaves the
  # config unset; the managed overlay registers one.
  defp placeholder_component do
    case Application.get_env(:tymeslot, :feature_placeholder_components) do
      nil -> nil
      placeholders -> placeholders[:group_bookings]
    end
  end
end
