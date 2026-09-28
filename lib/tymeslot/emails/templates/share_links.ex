defmodule Tymeslot.Emails.Templates.ShareLinks do
  @moduledoc """
  Email a host sends from the dashboard to invite someone to book: one button
  per shared link (booking page, public calendar, individual meeting types)
  plus an optional personal message.

  The recipient is not a user, so the email goes out in the host's own
  language (`users.locale`). Replies go to the host (`Reply-To`), not to the
  instance's sender address.
  """

  import Swoosh.Email

  alias Tymeslot.Emails.RecipientLocale
  alias Tymeslot.Emails.Shared.{Buttons, MjmlEmail, Sanitise, TemplateHelper, Text}
  alias Tymeslot.Profiles
  alias Tymeslot.ShareLinks

  use Gettext, backend: TymeslotWeb.Gettext

  @spec render(map(), [ShareLinks.link()], String.t(), String.t()) :: Swoosh.Email.t()
  def render(%{user: user} = profile, [_first | _rest] = links, recipient_email, message)
      when is_binary(recipient_email) and is_binary(message) do
    host_name = Profiles.display_name(profile) || MjmlEmail.fetch_from_name()

    Gettext.with_locale(TymeslotWeb.Gettext, RecipientLocale.locale_for(user), fn ->
      headline = dgettext("emails_booking", "Book a time with %{name}", name: host_name)

      intro =
        dgettext(
          "emails_booking",
          "%{name} has shared the links below so you can pick a time that suits you.",
          name: host_name
        )

      html_body =
        TemplateHelper.compile_system_template(
          mjml_content(intro, message, links),
          headline,
          headline,
          intent: :confirmed,
          eyebrow: dgettext("emails_booking", "Booking invitation"),
          stage_title: headline
        )

      MjmlEmail.base_email()
      |> to(recipient_email)
      |> reply_to({host_name, user.email})
      |> subject(
        Sanitise.sanitize_for_header(
          dgettext("emails_booking", "%{name} invites you to book a meeting", name: host_name)
        )
      )
      |> html_body(html_body)
      |> text_body(build_text_body(headline, intro, message, links))
    end)
  end

  defp mjml_content(intro, message, links) do
    """
    #{personal_message(message)}

    #{Text.centered_text(intro, padding: "4px 0 12px 0")}

    #{Enum.map_join(links, "\n", &Buttons.action_button(:confirmed, link_label(&1), &1.url, full_width: true))}
    """
  end

  defp personal_message(""), do: ""

  defp personal_message(message) do
    Text.centered_text(message, padding: "4px 0 16px 0", font_weight: "600")
  end

  defp build_text_body(headline, intro, message, links) do
    link_lines = Enum.map_join(links, "\n\n", &"#{link_label(&1)}:\n#{&1.url}")
    message_block = if message == "", do: "", else: "#{message}\n\n"

    """
    #{headline}

    #{message_block}#{intro}

    #{link_lines}
    """
  end

  defp link_label(%{kind: :booking_page}), do: dgettext("emails_booking", "Open booking page")

  defp link_label(%{kind: :calendar}),
    do: dgettext("emails_booking", "View availability calendar")

  defp link_label(%{kind: :meeting_type, name: name}),
    do: dgettext("emails_booking", "Book: %{meeting_type}", meeting_type: name)
end
