defmodule TymeslotWeb.Themes.Shared.AttendeeAttachmentUpload do
  @moduledoc """
  The booking-step side of booker attachments, shared by every scheduling
  theme's booking component.

  The upload is registered on the booking component's own socket, not the
  LiveView's: the booking form targets the component (`phx-target={@myself}`),
  and LiveView ties an upload to the socket whose form carries the
  `live_file_input`. Files are uploaded when the form is submitted
  (`auto_upload` off), so nothing reaches the server for a booking that is
  never sent.

  On submit the component consumes the entries into a fresh batch
  (`Tymeslot.Bookings.AttendeeAttachments`) and hands the stored files to the
  LiveView with a `{:step_event, :booking, :attachments, list}` message sent
  just before the `:submit` one, so the booking params stay plain form
  fields; `TymeslotWeb.Themes.Shared.BookingFlow` then owns the batch and
  deletes it if the booking does not go through.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Phoenix.Component, only: [assign: 3, upload_errors: 1, upload_errors: 2]
  import Phoenix.LiveView, only: [allow_upload: 3, consume_uploaded_entries: 3]

  require Logger

  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias TymeslotWeb.Helpers.UploadConstraints
  alias TymeslotWeb.Helpers.UploadHandler
  alias TymeslotWeb.Themes.Shared.BookingLocation

  @upload :attachments

  @doc """
  Whether the booking form on this socket offers the attachment field: the
  meeting type has it switched on, the admin allows at least one file type,
  and the booking is a real, new one (not a reschedule, whose meeting keeps
  its original files, and not an owner's preview, which persists nothing).
  """
  @spec enabled?(map()) :: boolean()
  def enabled?(assigns) do
    AttendeeAttachments.enabled_for?(assigns[:meeting_type]) and
      not (assigns[:is_rescheduling] || false) and
      not (assigns[:owner_preview] || false) and
      not (assigns[:theme_preview] || false)
  end

  @doc """
  Registers the upload on the booking component's socket, once, when the
  form offers it. Called from the component's `update/2`, since `mount/1`
  does not see the meeting type yet.
  """
  @spec maybe_allow(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def maybe_allow(socket) do
    if enabled?(socket.assigns) and not registered?(socket) do
      allow_upload(socket, @upload,
        accept: UploadConstraints.allowed_extensions(:booking_attachment),
        max_entries: UploadConstraints.max_entries(:booking_attachment),
        max_file_size: UploadConstraints.max_file_size(:booking_attachment)
      )
    else
      socket
    end
  end

  @doc """
  The booking component's `submit` handler: stores the attached files, then
  forwards the submission to the LiveView.

  Sets `:submitting` immediately for instant UI feedback — but only when the
  location picker has an answer the LiveView will accept. An incomplete one
  is refused without changing any assign the component renders, so a flag
  set here would have nothing to clear it again. The files stay selected in
  that case too: they are only consumed for a submission the LiveView will
  actually process. A rejected file stops the submission with
  `:attachment_error` set instead.
  """
  @spec submit(Phoenix.LiveView.Socket.t(), map()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def submit(socket, booking_params) do
    if BookingLocation.complete?(socket.assigns) do
      case consume(socket) do
        {:ok, socket} ->
          send(self(), {:step_event, :booking, :submit, booking_params})
          {:noreply, socket |> assign(:submitting, true) |> assign(:attachment_error, nil)}

        {:error, socket, message} ->
          {:noreply, assign(socket, :attachment_error, message)}
      end
    else
      send(self(), {:step_event, :booking, :submit, booking_params})
      {:noreply, assign(socket, :submitting, false)}
    end
  end

  # `{:ok, socket}` when there was nothing to store or everything was stored,
  # or `{:error, socket, message}` when a file was rejected, in which case the
  # whole batch is discarded and the booking must not be submitted.
  defp consume(socket) do
    if registered?(socket) do
      do_consume(socket)
    else
      {:ok, socket}
    end
  end

  defp do_consume(socket) do
    {socket, status} = UploadHandler.settle_upload(socket, @upload)

    case {status, UploadHandler.upload_entries(socket, @upload)} do
      {:in_progress, _entries} ->
        {:error, socket,
         dgettext("booking_attachments", "Your files are still uploading. Please wait.")}

      {:settled, []} ->
        {:ok, socket}

      {:settled, _entries} ->
        store_entries(socket)
    end
  end

  defp store_entries(socket) do
    batch = AttendeeAttachments.new_batch(socket.assigns.organizer_user_id)
    allowed = AttendeeAttachments.allowed_types()

    results =
      consume_uploaded_entries(socket, @upload, fn %{path: path}, entry ->
        {:ok, AttendeeAttachments.store(batch, path, entry.client_name, allowed)}
      end)

    stored = for {:ok, attachment} <- results, do: attachment

    case Enum.find(results, &match?({:error, _reason}, &1)) do
      nil ->
        send(self(), {:step_event, :booking, :attachments, stored})
        {:ok, socket}

      {:error, reason} ->
        Logger.info("Booker attachment rejected", reason: LogFormat.reason(reason))
        AttendeeAttachments.delete_batch(stored)
        {:error, socket, rejection_message(reason)}
    end
  end

  @doc """
  Human-readable problems with the files currently selected: one per rejected
  file plus any about the selection as a whole (too many files).
  """
  @spec error_messages(Phoenix.LiveView.UploadConfig.t()) :: [String.t()]
  def error_messages(upload) do
    config_errors = upload |> upload_errors() |> Enum.map(&upload_error_message(&1, nil))

    entry_errors =
      Enum.flat_map(upload.entries, fn entry ->
        upload
        |> upload_errors(entry)
        |> Enum.map(&upload_error_message(&1, entry.client_name))
      end)

    Enum.uniq(config_errors ++ entry_errors)
  end

  @doc "The note shown under the field: accepted types, per-file size and file count."
  @spec limits_note() :: String.t()
  def limits_note do
    max_files = UploadConstraints.max_entries(:booking_attachment)

    dngettext(
      "booking_attachments",
      "Allowed file types: %{types}, up to %{max_mb} MB, maximum %{count} file.",
      "Allowed file types: %{types}, up to %{max_mb} MB each, maximum %{count} files.",
      max_files,
      types: Enum.map_join(AttendeeAttachments.allowed_types(), ", ", &String.upcase/1),
      max_mb: div(UploadConstraints.max_file_size(:booking_attachment), 1_000_000)
    )
  end

  defp registered?(socket) do
    match?(%{@upload => _config}, socket.assigns[:uploads] || %{})
  end

  defp upload_error_message(:too_large, name) do
    dgettext("booking_attachments", "%{name} is larger than the allowed size.", name: name)
  end

  defp upload_error_message(:not_accepted, name) do
    dgettext("booking_attachments", "%{name} is not an allowed file type.", name: name)
  end

  defp upload_error_message(:too_many_files, _name) do
    dgettext("booking_attachments", "You have selected too many files.")
  end

  defp upload_error_message(_other, _name) do
    dgettext("booking_attachments", "A file could not be uploaded.")
  end

  defp rejection_message(:invalid_content) do
    dgettext(
      "booking_attachments",
      "One of your files does not match its file type and was not accepted. Please check it and select it again."
    )
  end

  defp rejection_message(:invalid_type) do
    dgettext("booking_attachments", "One of your files is not an allowed file type.")
  end

  defp rejection_message(_other) do
    dgettext("booking_attachments", "Your files could not be saved. Please try again.")
  end
end
