defmodule TymeslotWeb.Themes.Shared.Components.AttachmentField do
  @moduledoc """
  Shared "attach files" field for scheduling themes' booking forms.

  Renders the file input, the files chosen so far (each removable), any
  problems with them and a note with the admin's limits. It must sit inside
  the booking `<form>`: a `live_file_input` only uploads with the form that
  contains it. The upload itself is registered and consumed by
  `TymeslotWeb.Themes.Shared.AttendeeAttachmentUpload`; this component is
  purely presentational and sends `cancel_attachment` to `target`.

  Like `GuestField`, the markup ships no styling of its own — each theme
  styles the `attachment-*` classes in its own `booking-form.css`.
  """

  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Themes.Shared.AttendeeAttachmentUpload

  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :error, :string, default: nil
  attr :target, :any, required: true

  @spec attachment_field(map()) :: Phoenix.LiveView.Rendered.t()
  def attachment_field(assigns) do
    assigns =
      assigns
      |> assign(:errors, AttendeeAttachmentUpload.error_messages(assigns.upload))
      |> assign(:note, AttendeeAttachmentUpload.limits_note())

    ~H"""
    <div class="attachment-field" data-testid="attachment-field">
      <label for={@upload.ref} class="attachment-field__label">
        {dgettext("booking_attachments", "Attachments (optional)")}
      </label>

      <.live_file_input upload={@upload} class="attachment-field__input" />

      <p class="attachment-field__note">{@note}</p>

      <ul :if={@upload.entries != []} class="attachment-list">
        <li
          :for={entry <- @upload.entries}
          class="attachment-list__item"
          data-testid="attachment-entry"
        >
          <span class="attachment-list__name">{entry.client_name}</span>
          <span class="attachment-list__size">{format_size(entry.client_size)}</span>
          <button
            type="button"
            class="attachment-list__remove"
            phx-click="cancel_attachment"
            phx-value-ref={entry.ref}
            phx-target={@target}
            aria-label={dgettext("booking_attachments", "Remove %{name}", name: entry.client_name)}
          >
            ×
          </button>
        </li>
      </ul>

      <p :for={message <- @errors} class="attachment-field__error" role="alert">{message}</p>
      <p :if={@error} class="attachment-field__error" role="alert">{@error}</p>
    </div>
    """
  end

  @doc """
  The files the booker sent, listed on the confirmation step. Reuses the
  custom-answers classes both themes already style for that step.
  """
  attr :attachments, :list, required: true

  @spec submitted_attachments(map()) :: Phoenix.LiveView.Rendered.t()
  def submitted_attachments(assigns) do
    ~H"""
    <section
      :if={@attachments != []}
      class="custom-answers-section"
      data-testid="submitted-attachments"
    >
      <h3 class="custom-answers-heading">{dgettext("booking_attachments", "Your attachments")}</h3>
      <dl class="custom-answers-list">
        <div :for={attachment <- @attachments} class="custom-answer-row">
          <dt class="custom-answer-label">{attachment["filename"]}</dt>
          <dd class="custom-answer-value">{format_size(attachment["byte_size"])}</dd>
        </div>
      </dl>
    </section>
    """
  end

  defp format_size(bytes) when bytes >= 1_000_000,
    do: "#{Float.round(bytes / 1_000_000, 1)} MB"

  defp format_size(bytes), do: "#{max(1, div(bytes, 1000))} kB"
end
