defmodule TymeslotWeb.Themes.Quill.Scheduling.Components.BookingComponent do
  @moduledoc """
  Quill theme component for the booking/form step.
  Features glassmorphism design with elegant transparency effects.
  """
  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Meetings.Approval
  alias TymeslotWeb.Live.Scheduling.OrganizerHelpers
  alias TymeslotWeb.Themes.Shared.AttendeeAttachmentUpload
  alias TymeslotWeb.Themes.Shared.BookingLabels
  alias TymeslotWeb.Themes.Shared.BookingLocation
  alias TymeslotWeb.Themes.Shared.BookingText
  alias TymeslotWeb.Themes.Shared.Components.ApprovalNotice
  alias TymeslotWeb.Themes.Shared.Components.AttachmentField
  alias TymeslotWeb.Themes.Shared.Components.BookingForm
  alias TymeslotWeb.Themes.Shared.Components.GuestField
  alias TymeslotWeb.Themes.Shared.Components.LocationField
  alias TymeslotWeb.Themes.Shared.Components.OwnCalendar
  alias TymeslotWeb.Themes.Shared.GuestBooking
  alias TymeslotWeb.Themes.Shared.Journey.Runtime
  alias TymeslotWeb.Themes.Shared.LocalizationHelpers
  alias TymeslotWeb.Themes.Shared.SecurityFields
  alias TymeslotWeb.Themes.Shared.StepEvents

  use TymeslotWeb.Components.CoreComponents

  # `:uploads` is this component's own (see AttendeeAttachmentUpload), never
  # the parent's.
  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    {:ok, socket} = StepEvents.update(Map.delete(assigns, :uploads), socket)

    {:ok,
     socket
     |> assign_new(:attachment_error, fn -> nil end)
     |> AttendeeAttachmentUpload.maybe_allow()}
  end

  @impl Phoenix.LiveComponent
  def handle_event("submit", %{"booking" => booking_params}, socket),
    do: AttendeeAttachmentUpload.submit(socket, booking_params)

  def handle_event("cancel_attachment", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :attachments, ref)}

  defdelegate handle_event(event, params, socket), to: StepEvents

  @impl Phoenix.LiveComponent
  def render(assigns) do
    assigns = assign(assigns, :navigable_steps, Runtime.navigable_steps(assigns))
    assigns = assign(assigns, :next_day_end, LocalizationHelpers.booking_next_day_end(assigns))

    ~H"""
    <div class="container quill-container flex-1" data-locale={@locale}>
      <.page_layout
        show_steps={true}
        navigable_steps={@navigable_steps}
        current_step={3}
        slug={@duration}
        username_context={@username_context}
      >
        <div class="stack">
          <div class="flex-1 flex items-center justify-center px-4 py-4">
            <div class="w-full">
              <.glass_morphism_card class="booker-card booking-form-card">
                <div class="booking-card-body">
                  <h1 class="section-header booking-heading booking-heading-wrapper">
                    {dgettext("booking", "Enter Your Details")}
                  </h1>

                  <p class="booking-subtitle text-quill-primary">
                    <%= if @organizer_profile do %>
                      {dgettext("booking", "You're booking a %{duration} meeting with %{name}",
                        duration: BookingText.duration_label(assigns),
                        name: get_organizer_name(@organizer_profile, @username_context)
                      )}
                    <% else %>
                      {dgettext("booking", "You're booking a %{duration} meeting",
                        duration: BookingText.duration_label(assigns)
                      )}
                    <% end %>
                  </p>

                  <p class="booking-datetime text-quill-secondary">
                    {LocalizationHelpers.format_booking_datetime(
                      @selected_date,
                      @selected_time,
                      @user_timezone
                    )}
                  </p>
                  <p
                    :if={@next_day_end}
                    class="booking-datetime text-quill-secondary"
                    data-testid="booking-next-day-end"
                  >
                    {@next_day_end}
                  </p>

                  <LocationField.location_field
                    :if={BookingLocation.choice_required?(assigns)}
                    location_options={@location_options}
                    selected_location_id={@selected_location_id}
                    video_choices={BookingLocation.video_choices(assigns)}
                    selected_video_id={@selected_video_id}
                    venue_choices={BookingLocation.venue_choices(assigns)}
                    selected_venue_id={@selected_venue_id}
                    kept_location={BookingLocation.kept_location(assigns)}
                    location_phone={@location_phone}
                    location_error={@location_error}
                    phone_required={BookingLocation.phone_required?(assigns)}
                    target={@myself}
                  />

                  <LocationField.stated_location
                    :if={BookingLocation.stated_location?(assigns)}
                    option={BookingLocation.selected(assigns)}
                    venue_choices={BookingLocation.venue_choices(assigns)}
                  />

                  <BookingForm.booking_form
                    form={@form}
                    validation_errors={@validation_errors}
                    target={@myself}
                    class="space-y-2"
                    contact_class="booking-inline-fields"
                    notice={false}
                  >
                    <:extra_fields :let={f}>
                      <AttachmentField.attachment_field
                        :if={assigns[:uploads][:attachments]}
                        upload={@uploads.attachments}
                        error={@attachment_error}
                        target={@myself}
                      />

                      <OwnCalendar.field form={f} offer={assigns[:own_calendar_offer]} />
                      <OwnCalendar.signed_out_hint
                        login_path={assigns[:own_calendar_login_path]}
                        embedded={assigns[:embedded] || false}
                      />
                    </:extra_fields>
                    <GuestField.guest_field
                      :if={guests_allowed?(assigns)}
                      guest_emails={@guest_emails}
                      guest_input={@guest_input}
                      guest_error={@guest_error}
                      guests_open={@guests_open}
                      max_guests={@max_guests}
                      target={@myself}
                    />
                  </BookingForm.booking_form>

                  <ApprovalNotice.block
                    :if={Approval.required?(@meeting_type)}
                    organizer_name={get_organizer_name(@organizer_profile, @username_context)}
                    payment_required={@meeting_type.payment_required}
                    stage={:before}
                  />

                  <div class="booking-actions">
                    <.action_button
                      type="button"
                      phx-click="back_step"
                      phx-target={@myself}
                      data-testid="back-step"
                      data-intent="back"
                      variant={:secondary}
                      disabled={@submitting}
                      class="flex-1"
                    >
                      ← {dgettext("booking", "Back")}
                    </.action_button>

                    <.loading_button
                      type="submit"
                      form="booking-form"
                      id="submit-booking-button"
                      loading={@submitting}
                      loading_text={dgettext("booking", "Verifying...")}
                      disabled={!OrganizerHelpers.form_valid?(@form)}
                      data-testid="submit-booking"
                      data-intent="submit"
                      class="flex-1"
                      title={get_submit_title(@submitting, @form)}
                    >
                      {submit_label(@is_rescheduling, @meeting_type)}
                    </.loading_button>
                  </div>

                  <SecurityFields.recaptcha_notice_block />
                </div>
              </.glass_morphism_card>
            </div>
          </div>
        </div>
      </.page_layout>
    </div>
    """
  end

  # Helper functions

  # "Book" is a promise the button cannot keep on a gated meeting type, where
  # pressing it sends a request. Naming the action honestly is the cheapest
  # part of this whole feature and the one a visitor reads last — including
  # on a reschedule, which re-enters the approval gate on a gated type just
  # as a fresh submission does.
  defp submit_label(is_rescheduling, meeting_type) do
    BookingLabels.submit_label(
      is_rescheduling,
      meeting_type,
      dgettext("booking", "Book Meeting"),
      :quill
    )
  end

  defp guests_allowed?(assigns), do: GuestBooking.guests_allowed?(assigns)

  defp get_organizer_name(organizer_profile, username_context) do
    BookingLabels.organizer_display_name(organizer_profile, username_context)
  end

  defp get_submit_title(submitting, form) do
    cond do
      submitting ->
        dgettext("booking", "Verifying slot availability and creating your meeting...")

      !OrganizerHelpers.form_valid?(form) ->
        dgettext("booking", "Please fill in all required fields")

      true ->
        dgettext("booking", "Click to schedule your meeting")
    end
  end
end
