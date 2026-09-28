defmodule TymeslotWeb.Components.Dashboard.Meetings.DeleteMeetingModal do
  @moduledoc """
  Modal component for confirming permanent deletion of an already-cancelled
  meeting.

  Unlike cancelling, this is a hard delete
  (`Tymeslot.Meetings.delete_meeting_for_user/2`) — there is no undo.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers

  @doc """
  Renders a delete-meeting confirmation modal.

  ## Attributes

    * `id` - The modal ID (required)
    * `show` - Boolean to show/hide the modal (required)
    * `meeting` - The cancelled meeting to be deleted (required)
    * `timezone` - The timezone to display times in (optional, defaults to UTC)
    * `deleting` - Boolean indicating if deletion is in progress (required)
    * `on_cancel` - JS command to execute when closing the modal (required)
    * `confirm_event` - Event name pushed when the form is submitted (required)
    * `target` - phx-target reference for the confirm event (required)
  """
  attr :id, :string, required: true
  attr :show, :boolean, required: true
  attr :meeting, :map, required: true
  attr :timezone, :string, default: "UTC"
  attr :time_format, :string, default: "24h"
  attr :deleting, :boolean, required: true
  attr :on_cancel, JS, required: true
  attr :confirm_event, :string, required: true
  attr :target, :any, required: true

  @spec delete_meeting_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def delete_meeting_modal(assigns) do
    ~H"""
    <CoreComponents.modal id={@id} show={@show} on_cancel={@on_cancel} size={:medium}>
      <:header>
        <div class="flex items-center gap-2">
          <CoreComponents.icon name="hero-trash" class="w-5 h-5 text-red-500" />
          {dgettext("dashboard_bookings", "Delete Meeting")}
        </div>
      </:header>

      <form :if={@meeting} id="delete-meeting-form" phx-submit={@confirm_event} phx-target={@target}>
        <p class="text-neutral-300 font-medium text-lg leading-relaxed">
          {dgettext(
            "dashboard_bookings",
            "Permanently delete the cancelled meeting with %{name} scheduled for %{when}?",
            name: @meeting.attendee_name,
            when:
              "#{Helpers.format_meeting_date(@meeting, @timezone)} • #{Helpers.format_meeting_time(@meeting, @timezone, @time_format)}"
          )}
        </p>

        <p class="mt-4 text-neutral-400 font-medium">
          {dgettext("dashboard_bookings", "This action cannot be undone.")}
        </p>
      </form>

      <:footer>
        <div class="flex justify-end gap-3">
          <CoreComponents.action_button variant={:secondary} phx-click={@on_cancel}>
            {dgettext("dashboard_bookings", "Keep")}
          </CoreComponents.action_button>
          <CoreComponents.loading_button
            type="submit"
            form="delete-meeting-form"
            variant={:danger}
            loading={@deleting}
            loading_text={dgettext("dashboard_bookings", "Deleting...")}
          >
            {dgettext("dashboard_bookings", "Delete Meeting")}
          </CoreComponents.loading_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end
end
