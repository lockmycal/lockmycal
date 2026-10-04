defmodule Tymeslot.Emails.Shared.Meeting.AttendeeAttachments do
  @moduledoc """
  The files a booker attached (`Tymeslot.Bookings.AttendeeAttachments`) in the
  organiser's booking emails: a list of them in the body, and the files
  themselves attached to the message.

  The files are only attached while their total stays under 15 MB,
  comfortably inside what mail servers accept
  in one message (commonly 20–25 MB, and a file grows by a third once base64
  encoded). Over that, the body says so and points to the dashboard, where
  every file can always be downloaded. A file that has gone missing from disk
  is skipped rather than failing the email.

  Never used for the booker's own emails: they sent the files.
  """

  alias Swoosh.Attachment
  alias Swoosh.Email
  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Emails.Shared.{Sanitise, Styles}
  alias Tymeslot.Utils.UrlBuilder

  use Gettext, backend: TymeslotWeb.Gettext

  @max_attached_bytes 15_000_000

  @doc "Whether the files fit into one email, and so are attached to it."
  @spec attachable?([map()]) :: boolean()
  def attachable?(attachments) do
    attachments |> Enum.map(&(&1["byte_size"] || 0)) |> Enum.sum() <= @max_attached_bytes
  end

  @doc "Adds the files to `email` when they fit (see `attachable?/1`)."
  @spec attach(Swoosh.Email.t(), [map()]) :: Swoosh.Email.t()
  def attach(email, attachments) do
    if attachments != [] and attachable?(attachments) do
      Enum.reduce(attachments, email, &attach_file/2)
    else
      email
    end
  end

  defp attach_file(attachment, email) do
    with {:ok, path} <- AttendeeAttachments.absolute_path(attachment),
         {:ok, bytes} <- File.read(path) do
      Email.attachment(
        email,
        Attachment.new({:data, bytes},
          filename: attachment["filename"],
          content_type: attachment["content_type"]
        )
      )
    else
      _missing -> email
    end
  end

  @doc "The HTML list of files for the organiser's email body, or `\"\"`."
  @spec section([map()]) :: String.t()
  def section([]), do: ""

  def section(attachments) do
    rows =
      Enum.map_join(attachments, "\n", fn attachment ->
        """
        <tr style="#{Styles.table_row_style()}">
          <td style="#{Styles.table_label_style()}">#{Sanitise.sanitize_for_email(attachment["filename"] || "")}</td>
          <td style="#{Styles.table_value_style()}">#{format_size(attachment["byte_size"])}</td>
        </tr>
        """
      end)

    """
    <mj-section padding="8px 0 20px 0">
      <mj-column>
        <mj-text
          font-size="11px"
          font-weight="700"
          color="#{Styles.ink_muted()}"
          letter-spacing="0.14em"
          text-transform="uppercase"
          padding="0 0 12px 0"
        >
          #{dgettext("emails", "Attachments")}
        </mj-text>
        <mj-table #{Styles.table_attributes()} css-class="responsive-table">
          #{rows}
        </mj-table>
        <mj-text font-size="13px" color="#{Styles.ink_muted()}" line-height="19px" padding="8px 0 0 0">
          #{Sanitise.sanitize_for_email(delivery_note(attachments))}
        </mj-text>
      </mj-column>
    </mj-section>
    """
  end

  @doc "The plain-text list of files for the organiser's email body, or `\"\"`."
  @spec text_section([map()]) :: String.t()
  def text_section([]), do: ""

  def text_section(attachments) do
    lines =
      Enum.map_join(attachments, "\n", fn attachment ->
        "- #{attachment["filename"]} (#{format_size(attachment["byte_size"])})"
      end)

    """

    #{dgettext("emails", "ATTACHMENTS:")}
    #{lines}
    #{delivery_note(attachments)}
    """
  end

  defp delivery_note(attachments) do
    if attachable?(attachments) do
      dgettext("emails", "The files are attached to this email.")
    else
      dgettext(
        "emails",
        "The files are too large to attach to this email. Download them from the booking on your dashboard: %{url}",
        url: UrlBuilder.build_url("/dashboard/meetings")
      )
    end
  end

  defp format_size(bytes) when is_integer(bytes) and bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp format_size(bytes) when is_integer(bytes), do: "#{max(1, div(bytes, 1000))} kB"
  defp format_size(_unknown), do: ""
end
