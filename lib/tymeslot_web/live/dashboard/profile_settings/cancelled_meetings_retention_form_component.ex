defmodule TymeslotWeb.Dashboard.ProfileSettings.CancelledMeetingsRetentionFormComponent do
  @moduledoc """
  Lets the organizer opt in to automatically deleting their own cancelled
  meetings once a configurable number of days have passed since cancellation.

  Deletion is always scoped to the organizer's own meetings and runs nightly
  via `Tymeslot.Workers.DeleteCancelledMeetingsWorker` — this component only
  manages the two settings (`auto_delete_cancelled_meetings_enabled`,
  `auto_delete_cancelled_meetings_after_days`) that worker reads.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Profiles
  alias Tymeslot.Validation.Constraints

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl Phoenix.LiveComponent
  def handle_event("toggle_auto_delete_cancelled_meetings", %{"state" => state}, socket) do
    profile = socket.assigns.profile
    enabled = state == "true"

    case Profiles.update_profile_field(
           profile,
           :auto_delete_cancelled_meetings_enabled,
           enabled
         ) do
      {:ok, updated_profile} ->
        send(self(), {:profile_updated, updated_profile})
        Flash.info(auto_delete_flash_message(enabled))
        {:noreply, assign(socket, profile: updated_profile)}

      {:error, _changeset} ->
        Flash.error(
          dgettext("dashboard_profile", "Failed to update cancelled meeting cleanup setting")
        )

        {:noreply, socket}
    end
  end

  def handle_event("update_auto_delete_cancelled_meetings_after_days", params, socket) do
    profile = socket.assigns.profile
    after_days = params["after_days"] || params["value"]

    case Profiles.update_profile_field(
           profile,
           :auto_delete_cancelled_meetings_after_days,
           after_days
         ) do
      {:ok, updated_profile} ->
        send(self(), {:profile_updated, updated_profile})
        Flash.info(dgettext("dashboard_profile", "Cleanup delay updated"))
        {:noreply, assign(socket, profile: updated_profile)}

      {:error, changeset} ->
        Flash.error(retention_days_error_message(changeset))
        {:noreply, socket}
    end
  end

  defp auto_delete_flash_message(true),
    do:
      dgettext(
        "dashboard_profile",
        "Cancelled meetings will now be deleted automatically after the configured delay"
      )

  defp auto_delete_flash_message(false),
    do:
      dgettext("dashboard_profile", "Cancelled meetings will no longer be deleted automatically")

  defp retention_days_error_message(changeset) do
    range = Constraints.cancelled_meeting_retention_days_range()

    case changeset.errors[:auto_delete_cancelled_meetings_after_days] do
      nil ->
        dgettext("dashboard_profile", "Failed to update cleanup delay")

      _error ->
        dgettext(
          "dashboard_profile",
          "Cleanup delay must be between %{min} and %{max} days",
          min: range.first,
          max: range.last
        )
    end
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    range = Constraints.cancelled_meeting_retention_days_range()
    assigns = assign(assigns, min_days: range.first, max_days: range.last)

    ~H"""
    <div id="cancelled-meetings-retention-form-container">
      <.subsection_header
        icon="hero-trash"
        title={dgettext("dashboard_profile", "Cancelled Meetings")}
        class="mb-3"
      />
      <div class="input p-4">
        <div class="flex items-center justify-between gap-4">
          <span class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_profile", "Automatically delete cancelled meetings?")}
          </span>
          <.enabled_toggle
            active={(@profile && @profile.auto_delete_cancelled_meetings_enabled) || false}
            click_event="toggle_auto_delete_cancelled_meetings"
            target={@myself}
            aria_label={dgettext("dashboard_profile", "Set automatic cancelled meeting cleanup")}
          />
        </div>

        <div :if={@profile && @profile.auto_delete_cancelled_meetings_enabled} class="mt-4">
          <.input
            type="number"
            name="after_days"
            label={dgettext("dashboard_profile", "Delete after (days since cancellation)")}
            value={@profile.auto_delete_cancelled_meetings_after_days}
            min={@min_days}
            max={@max_days}
            step="1"
            phx-change="update_auto_delete_cancelled_meetings_after_days"
            phx-debounce="500"
            phx-target={@myself}
          />
        </div>
      </div>
      <p class="mt-4 text-token-sm text-neutral-600 dark:text-twilight-indigo-200 font-medium leading-relaxed">
        {dgettext(
          "dashboard_profile",
          "A nightly job permanently deletes your own cancelled meetings once they've been cancelled for longer than this delay. This cannot be undone."
        )}
      </p>
    </div>
    """
  end
end
