defmodule TymeslotWeb.Dashboard.ServiceSettings.ComponentView do
  @moduledoc """
  Markup for the meeting (service) settings component.

  Extracted from `ServiceSettingsComponent` so that module stays focused on lifecycle
  and event routing, matching how `CalendarSettings.ComponentView` sits behind
  `CalendarSettingsComponent`. `settings/1` receives the component's assigns
  unchanged (its `render/1` delegates straight to it), so LiveView change
  tracking is preserved.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.MeetingTypes
  alias Tymeslot.Scheduling.LinkAccessPolicy
  alias Tymeslot.ShareLinks
  alias TymeslotWeb.Components.Dashboard.MeetingTypes.BookingLinkModal
  alias TymeslotWeb.Components.Dashboard.MeetingTypes.DeleteMeetingTypeModal
  alias TymeslotWeb.Components.Dashboard.ProBadge
  alias TymeslotWeb.Components.Dashboard.ProNotice
  alias TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm
  alias TymeslotWeb.Dashboard.MeetingSettings.MeetingTypesListComponent
  alias TymeslotWeb.Dashboard.MeetingSettings.SchedulingSettingsComponent
  alias TymeslotWeb.Endpoint

  @spec settings(map()) :: Phoenix.LiveView.Rendered.t()
  def settings(assigns) do
    ~H"""
    <div class="space-y-10 pb-20">
      <.section_header
        icon="hero-squares-2x2"
        title={dgettext("dashboard_integrations", "Meeting Types")}
        subtitle={
          dgettext(
            "dashboard_integrations",
            "Create and manage the meeting types guests can book with you."
          )
        }
      />

      <div
        :if={!@show_add_form and !@editing_type and @meeting_types != []}
        class="flex justify-end"
      >
        <MeetingTypesListComponent.add_meeting_type_button parent_myself={@myself} />
      </div>

      <%= if (@show_edit_overlay && @editing_type) || @show_add_form do %>
        <%!-- Form View (Add or Edit) --%>
        <div
          id="meeting-type-config-view"
          phx-hook="ScrollReset"
          data-action={if @editing_type, do: "edit-#{@editing_type.id}", else: "new"}
          class="space-y-8"
        >
          <.card class="space-y-4">
            <%!-- Title passed as the slot, not `title`, so the Pro badge sits right
                  after it instead of at the far end of the row. --%>
            <.section_header level={2} icon="hero-squares-2x2">
              <span class="inline-flex items-center gap-3">
                {if @editing_type,
                  do: dgettext("dashboard_integrations", "Edit Meeting Type"),
                  else: dgettext("dashboard_integrations", "Add Meeting Type")}
                <ProBadge.pro_badge
                  :if={@editing_type && !@custom_booking_link_allowed}
                  data-testid="booking-link-pro-badge"
                />
              </span>
              <:actions>
                <.icon_button
                  icon="hero-x-mark"
                  label={dgettext("dashboard_integrations", "Close")}
                  phx-click={if @editing_type, do: "close_edit_overlay", else: "toggle_add_form"}
                  phx-target={@myself}
                />
              </:actions>
            </.section_header>

            <%!-- Direct booking link, always at hand while editing (needs a username) --%>
            <div :if={@editing_type && booking_base_url(@profile)} class="space-y-2">
              <div class="flex flex-wrap items-center gap-2">
                <input
                  type="text"
                  readonly
                  aria-label={dgettext("dashboard_integrations", "Direct booking link")}
                  value={"#{booking_base_url(@profile)}/#{MeetingTypes.effective_slug(@editing_type)}"}
                  class={[
                    "font-mono text-token-sm flex-1 min-w-[12rem] px-4 py-2.5 rounded-token-xl border-2 border-neutral-300 bg-neutral-50 text-neutral-600 cursor-default dark:border-twilight-indigo-700 dark:bg-twilight-indigo-900/60 dark:text-twilight-indigo-100",
                    !@custom_booking_link_allowed && "opacity-60 cursor-not-allowed"
                  ]}
                />
                <.action_button
                  type="button"
                  variant={:secondary}
                  id={"copy-booking-link-#{@editing_type.id}"}
                  phx-hook="CopyOnClick"
                  data-copy-text={"#{booking_base_url(@profile)}/#{MeetingTypes.effective_slug(@editing_type)}"}
                  data-copy-feedback={dgettext("dashboard_integrations", "Booking link copied!")}
                >
                  {dgettext("dashboard_integrations", "Copy")}
                </.action_button>
                <.action_button
                  :if={
                    @editing_type.is_active &&
                      LinkAccessPolicy.can_link?(@profile, @integration_status)
                  }
                  type="button"
                  variant={:secondary}
                  id={"email-booking-link-#{@editing_type.id}"}
                  phx-click="open"
                  phx-value-preselect={ShareLinks.meeting_type_key(@editing_type)}
                  phx-target="#share-links-modal"
                >
                  {dgettext("dashboard_meeting_types", "Send by email")}
                </.action_button>
                <.action_button
                  type="button"
                  variant={:secondary}
                  disabled={!@custom_booking_link_allowed}
                  phx-click="open_slug_modal"
                  phx-target={@myself}
                >
                  {dgettext("dashboard_integrations", "Change link")}
                </.action_button>
              </div>
              <p class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200">
                {dgettext(
                  "dashboard_integrations",
                  "Anyone with this link can book this meeting type directly, without seeing your other meeting types."
                )}
              </p>
              <ProNotice.pro_notice
                :if={!@custom_booking_link_allowed}
                data-testid="booking-link-pro-note"
              >
                {dgettext(
                  "dashboard_integrations",
                  "Changing the link is only available on the Pro plan and above."
                )}
              </ProNotice.pro_notice>
            </div>
          </.card>

          <%!-- One form for both adding and editing. `form_id` is fixed
                when the form opens and survives creation, so a new
                meeting type switches to edit mode in place. --%>
          <.live_component
            module={MeetingTypeForm}
            id={@form_id}
            type={@editing_type}
            is_edit={!!@editing_type}
            video_integrations={@video_integrations}
            venues={@venues}
            calendar_integrations={@calendar_integrations}
            parent_myself={@myself}
            current_user={@current_user}
            client_ip={@client_ip}
            user_agent={@user_agent}
            custom_questions_allowed={@custom_questions_allowed}
            group_bookings_allowed={@group_bookings_allowed}
          />

          <BookingLinkModal.booking_link_modal
            show={@show_slug_modal}
            meeting_type={@slug_modal_type}
            slug_draft={@slug_draft}
            base_url={booking_base_url(@profile) || ""}
            myself={@myself}
          />
        </div>
      <% else %>
        <%!-- Normal View --%>
        <div class="space-y-10">
          <%!-- Meeting Types Section --%>
          <div class="space-y-6">
            <MeetingTypesListComponent.meeting_types_section
              meeting_types={@meeting_types}
              schedules={@schedules}
              show_add_form={@show_add_form}
              editing_type={@editing_type}
              currency={@payment_currency}
              venues={@venues}
              group_bookings_allowed={@group_bookings_allowed}
              parent_myself={@myself}
              can_share={LinkAccessPolicy.can_link?(@profile, @integration_status)}
            />
          </div>

          <%!-- Scheduling Settings --%>
          <div>
            <.live_component
              module={SchedulingSettingsComponent}
              id="scheduling-settings"
              profile={@profile}
              client_ip={@client_ip}
              user_agent={@user_agent}
            />
          </div>
        </div>

        <%!-- Delete Meeting Type Modal --%>
        <DeleteMeetingTypeModal.delete_meeting_type_modal
          show={@show_delete_meeting_type_modal}
          meeting_type={@delete_meeting_type_modal_data}
          myself={@myself}
        />
      <% end %>
    </div>
    """
  end

  # The public base of a meeting type's booking link, e.g. "https://host/alice".
  # Returns nil when the profile has no username yet (link UI is then hidden).
  defp booking_base_url(%{username: username}) when is_binary(username) and username != "" do
    Endpoint.url() <> "/" <> username
  end

  defp booking_base_url(_profile), do: nil
end
