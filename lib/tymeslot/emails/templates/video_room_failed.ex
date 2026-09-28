defmodule Tymeslot.Emails.Templates.VideoRoomFailed do
  @moduledoc """
  MJML template for the "we couldn't set up video conferencing" notification
  sent to the meeting organizer.

  Rendered in the organizer's locale. The caller establishes it from
  `organizer_user_id` via `Tymeslot.Emails.RecipientLocale`; this module only
  reads the ambient locale for the pure date and time formatting.
  """

  alias Tymeslot.Emails.Shared.{
    Callouts,
    Formatting,
    MeetingComponents,
    Styles,
    TemplateHelper,
    Text,
    TimezoneHelper
  }

  alias Tymeslot.Profiles

  use Gettext, backend: TymeslotWeb.Gettext

  # A meeting-setup problem the user needs to act on.
  @intent :alert

  @type meeting_map :: %{
          required(:start_time) => DateTime.t(),
          required(:duration) => integer(),
          required(:location) => String.t() | nil,
          optional(:organizer_user_id) => term(),
          optional(atom()) => term()
        }

  @doc """
  Returns `{html_body, text_body}`, computing the organizer's local start time only once.
  Prefer this over calling `render/1` and `render_text/1` separately when both bodies are needed.
  """
  @spec render_both(meeting_map()) :: {String.t(), String.t()}
  def render_both(meeting) do
    owner_start_time = owner_start_time(meeting)
    {do_render_html(owner_start_time, meeting), do_render_text(owner_start_time, meeting)}
  end

  @spec render(meeting_map()) :: String.t()
  def render(meeting), do: do_render_html(owner_start_time(meeting), meeting)

  @spec render_text(meeting_map()) :: String.t()
  def render_text(meeting), do: do_render_text(owner_start_time(meeting), meeting)

  defp do_render_html(owner_start_time, meeting) do
    locale = Gettext.get_locale(TymeslotWeb.Gettext)

    mjml_content = """
    #{Callouts.alert_box(:cancelled,
    dgettext("emails", "I wasn't able to set up video conferencing for this meeting. The appointment itself has been successfully confirmed and both you and the attendee have received confirmation emails — you'll just need to arrange another way to meet, or set up video conferencing manually."),
    title: dgettext("emails", "Video Setup Failed"))}

    #{Text.title_section(dgettext("emails", "Meeting Details"))}
    #{MeetingComponents.meeting_details_table(%{date: owner_start_time, start_time: owner_start_time, duration: meeting.duration, location: meeting.location}, locale)}

    #{Text.divider()}

    #{Text.title_section(dgettext("emails", "What you can do"))}

    <mj-text color="#{Styles.ink_soft()}">
      #{dgettext("emails", "Both you and the attendee already have your confirmation emails, so the booking itself is unaffected — this is purely a video setup issue. Consider sending the attendee a video link manually, switching your video provider, or reconnecting it from your dashboard's Video settings.")}
    </mj-text>

    #{Text.system_footer_note(dgettext("emails", "This is an automated system notification. Please check your video integration settings if this issue persists."))}
    """

    TemplateHelper.compile_system_template(
      mjml_content,
      dgettext("emails", "Video Setup Failed"),
      dgettext("emails", "Video conferencing could not be set up for your meeting."),
      intent: @intent,
      eyebrow: dgettext("emails", "Action required"),
      stage_title: dgettext("emails", "Video didn't set up"),
      stage_subtitle:
        dgettext("emails", "The booking is safe - but video conferencing needs your attention.")
    )
  end

  defp do_render_text(owner_start_time, meeting) do
    locale = Gettext.get_locale(TymeslotWeb.Gettext)

    """
    #{dgettext("emails", "Video Setup Failed")}

    #{dgettext("emails", "I wasn't able to set up video conferencing for this meeting. The appointment itself has been successfully confirmed and both you and the attendee have received confirmation emails — you'll just need to arrange another way to meet, or set up video conferencing manually.")}

    #{dgettext("emails", "MEETING DETAILS:")}
    #{dgettext("emails", "Date:")} #{Formatting.format_date(owner_start_time, locale)}
    #{dgettext("emails", "Time:")} #{Formatting.format_time(owner_start_time, locale)}
    #{dgettext("emails", "Duration:")} #{Formatting.format_duration(meeting.duration, locale)}
    #{dgettext("emails", "Location:")} #{meeting.location || dgettext("emails", "Not specified")}

    #{dgettext("emails", "WHAT YOU CAN DO:")}
    #{dgettext("emails", "Both you and the attendee already have your confirmation emails, so the booking itself is unaffected — this is purely a video setup issue. Consider sending the attendee a video link manually, switching your video provider, or reconnecting it from your dashboard's Video settings.")}

    #{dgettext("emails", "This is an automated system notification. Please check your video integration settings if this issue persists.")}
    """
  end

  defp owner_start_time(meeting) do
    owner_timezone =
      case meeting.organizer_user_id do
        nil -> Profiles.get_default_timezone()
        user_id -> Profiles.get_user_timezone(user_id)
      end

    TimezoneHelper.convert_to_timezone(meeting.start_time, owner_timezone)
  end
end
