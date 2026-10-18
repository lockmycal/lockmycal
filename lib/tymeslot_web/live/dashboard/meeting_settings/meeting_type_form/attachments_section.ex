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
      <.subsection_header
        icon="hero-paper-clip"
        title={dgettext("dashboard_meeting_form", "Attachments")}
      />

      <.setting_row
        id="allow-attachments-toggle"
        control={:switch}
        label={dgettext("dashboard_meeting_form", "Let invitees attach files to their booking")}
        description={
          if @types != [],
            do:
              dgettext(
                "dashboard_meeting_form",
                "Files are private: you download them from the booking on your dashboard and receive them with the booking email."
              )
        }
        checked={@allow_attachments}
        phx-value-state={to_string(!@allow_attachments)}
        disabled={@types == []}
        on_change="toggle_allow_attachments"
        target={@myself}
      >
        <:disabled_reason>
          {dgettext(
            "dashboard_meeting_form",
            "Your administrator has switched file attachments off for this installation."
          )}
        </:disabled_reason>
      </.setting_row>

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
    </section>
    """
  end

  defp format_types(types), do: Enum.map_join(types, ", ", &String.upcase/1)
end
