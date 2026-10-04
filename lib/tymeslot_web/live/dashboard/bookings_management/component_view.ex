defmodule TymeslotWeb.Dashboard.BookingsManagement.ComponentView do
  @moduledoc """
  Markup for the bookings management component.

  Extracted from `BookingsManagementComponent` so that module stays focused
  on lifecycle and event routing, matching how `ServiceSettings.ComponentView`
  sits behind `ServiceSettingsComponent`. `management/1` receives the
  component's assigns unchanged (its `render/1` delegates straight to it), so
  LiveView change tracking is preserved.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config
  alias TymeslotWeb.Components.Dashboard.Meetings.Helpers
  alias TymeslotWeb.Components.Dashboard.Meetings.MeetingListComponents
  alias TymeslotWeb.Dashboard.BookingsManagement.Modals

  alias TymeslotWeb.Dashboard.CalendarGrid.Modals.{ConfirmDiscardAttendeesModal, CreateEventModal}

  @spec management(map()) :: Phoenix.LiveView.Rendered.t()
  def management(assigns) do
    ~H"""
    <div id="bookings-management" class="space-y-10 pb-20">
      <div>
        <.section_header
          icon="hero-calendar-days"
          title={dgettext("dashboard_bookings", "Meetings")}
          subtitle={
            dgettext(
              "dashboard_bookings",
              "View and manage your scheduled meetings. It only shows meetings that are scheduled with your %{app_name} account. All meetings are shown in calendar.",
              app_name: Config.app_name()
            )
          }
        />

        <div class="mb-10">
          <MeetingListComponents.filter_tabs
            active={@filter}
            awaiting_approval_count={@awaiting_approval_count}
            upcoming_count={@upcoming_count}
            past_count={@past_count}
            cancelled_count={@cancelled_count}
            target={@myself}
          />
        </div>

        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 mb-4">
          <.subsection_header
            icon="hero-queue-list"
            title={dgettext("dashboard_bookings", "Meetings List")}
          />
          <button
            type="button"
            phx-click="show_create_form"
            phx-target={@myself}
            class="btn btn-primary"
          >
            <.icon name="hero-plus" class="w-5 h-5" />
            {dgettext("dashboard_bookings", "Add meeting")}
          </button>
        </div>

        <MeetingListComponents.meetings_list
          loading={@loading}
          is_empty={@is_empty}
          meetings_stream={@streams.meetings}
          filter={@filter}
          profile={@profile}
          time_format={@time_format}
          cancelling_meeting={@cancelling_meeting}
          sending_reschedule={@sending_reschedule}
          answering_request={@answering_request}
          deleting_meeting={@deleting_meeting}
          current_user_email={@current_user.email}
          target={@myself}
        />

        <MeetingListComponents.load_more
          has_more={@has_more}
          loading_more={@loading_more}
          target={@myself}
        />

        <div :if={@is_empty} class="mt-16">
          <.subsection_header
            icon="hero-calendar-days"
            title={dgettext("dashboard_bookings", "Meeting Management")}
            class="mb-6"
          />
          <MeetingListComponents.info_panel />
        </div>
      </div>

      <CreateEventModal.create_event_modal
        :if={@creating_event}
        creating_event={@creating_event}
        integrations={@integrations}
        integration_colors={@integration_colors}
        saving={@saving_event}
        user_timezone={Helpers.get_meeting_timezone(nil, @profile)}
        myself={@myself}
        video_integrations={@video_integrations}
        contacts_allowed={@contacts_allowed}
        contact_picker_query={@contact_picker_query}
        contact_picker_open={@contact_picker_open}
        contact_picker_results={@contact_picker_results}
      />

      <ConfirmDiscardAttendeesModal.confirm_discard_attendees_modal
        :if={@confirm_discard_attendees}
        count={length((@creating_event && @creating_event[:attendees]) || [])}
        myself={@myself}
      />

      <Modals.booking_modals
        cancel_meeting={@cancel_meeting_modal_data}
        show_cancel={@show_cancel_meeting_modal || false}
        cancel_booking_payment={@cancel_booking_payment}
        cancelling={@cancelling_meeting != nil}
        decline_request={@decline_request_modal_data}
        show_decline={@show_decline_request_modal || false}
        declining={@answering_request != nil}
        reschedule_request={@reschedule_request_modal_data}
        show_reschedule={@show_reschedule_request_modal || false}
        sending_reschedule={@sending_reschedule}
        delete_meeting={@delete_meeting_modal_data}
        show_delete={@show_delete_meeting_modal || false}
        deleting={@deleting_meeting != nil}
        add_guests={@add_guests_modal_data}
        show_add_guests={@show_add_guests_modal || false}
        staged_guests={@staged_guests}
        existing_guests={@add_guests_existing}
        profile={@profile}
        time_format={@time_format}
        target={@myself}
      />
    </div>
    """
  end
end
