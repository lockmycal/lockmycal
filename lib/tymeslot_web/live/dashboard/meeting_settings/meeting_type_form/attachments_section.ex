defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.AttachmentsSection do
  @moduledoc """
  Stateless function component for the meeting-type form's Attachments
  section.

  Renders the "let invitees attach files" toggle. Which file types are
  accepted, how large each file may be and how many a booking may carry are
  instance-wide admin settings (`Tymeslot.AppSettings`), so the host can only
  switch the field on or off; the current limits are shown so they know what
  their invitees will be allowed to send. When the admin allows no file type
  at all the toggle is disabled. The toggle dispatches
  `toggle_allow_attachments` back to the parent `MeetingTypeForm`
  (`@myself`), which owns the socket state and auto-save.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.AppSettings
  alias Tymeslot.Bookings.AttendeeAttachments

  attr :allow_attachments, :boolean, required: true
  attr :myself, :any, required: true

  @spec attachments_section(map()) :: Phoenix.LiveView.Rendered.t()
  def attachments_section(assigns) do
    assigns =
      assigns
      |> assign(:types, AttendeeAttachments.allowed_types())
      |> assign(:max_mb, AppSettings.get(:max_booking_attachment_size_mb))
      |> assign(:max_files, AppSettings.get(:max_booking_attachments))

    ~H"""
    <section class="space-y-4">
      <div class="flex items-center gap-2">
        <.icon name="hero-paper-clip" class="w-5 h-5 text-primary-500" />
        <h3 class="text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
          {dgettext("dashboard_meeting_form", "Attachments")}
        </h3>
      </div>

      <div class="card-glass p-4 flex items-center justify-between gap-4 flex-wrap">
        <div class="min-w-0 flex-1 space-y-1">
          <p class="text-token-sm font-medium text-neutral-700 dark:text-neutral-200">
            {dgettext("dashboard_meeting_form", "Let invitees attach files to their booking")}
          </p>
          <p
            :if={@types != []}
            class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200"
          >
            {dgettext(
              "dashboard_meeting_form",
              "Files are private: you download them from the booking on your dashboard and receive them with the booking email."
            )}
          </p>
          <p
            :if={@types != [] && @allow_attachments}
            id="meeting-type-attachment-limits"
            class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200"
          >
            {dngettext(
              "dashboard_meeting_form",
              "Allowed: %{types}, up to %{max_mb} MB per file, %{count} file per booking. Your administrator sets these limits.",
              "Allowed: %{types}, up to %{max_mb} MB per file, up to %{count} files per booking. Your administrator sets these limits.",
              @max_files,
              types: format_types(@types),
              max_mb: @max_mb
            )}
          </p>
          <p
            :if={@types == []}
            class="text-token-sm text-neutral-500 dark:text-twilight-indigo-200"
          >
            {dgettext(
              "dashboard_meeting_form",
              "Your administrator has switched file attachments off for this installation."
            )}
          </p>
        </div>
        <.enabled_toggle
          active={@allow_attachments}
          click_event="toggle_allow_attachments"
          target={@myself}
          disabled={@types == []}
          aria_label={dgettext("dashboard_meeting_form", "Let invitees attach files")}
        />
      </div>
    </section>
    """
  end

  defp format_types(types), do: Enum.map_join(types, ", ", &String.upcase/1)
end
