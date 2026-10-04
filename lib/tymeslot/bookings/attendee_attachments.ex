defmodule Tymeslot.Bookings.AttendeeAttachments do
  @moduledoc """
  Files a booker attaches on the public booking page.

  They are personal data meant for the organiser only, so they live under
  `:private_upload_directory`, which, unlike `:upload_directory`, is never
  served by `Plug.Static`; the organiser downloads them through
  `TymeslotWeb.MeetingAttachmentController`, which checks ownership.

  Layout: `booking_attachments/<organizer user id>/<batch id>/<file id>.<ext>`.
  A batch is the set of files one booking submission brought in. Files are
  stored before the meeting row exists (the upload has to be consumed while
  the LiveView still holds it), so a booking that then fails leaves a batch
  no meeting points at; the caller deletes it on the failure path, and
  `prune_orphans/0` catches whatever slips through (a crash between storing
  and inserting, an unpaid booking that expired, meetings deleted in bulk).

  Each stored file is described by a string-keyed map, the shape
  `meetings.attendee_attachments` holds:

      %{"id" => uuid, "filename" => original display name,
        "stored_path" => relative path, "content_type" => mime,
        "byte_size" => integer}
  """

  require Logger

  alias Ecto.UUID
  alias Tymeslot.AppSettings
  alias Tymeslot.Clock
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Meetings.MeetingQueries
  alias Tymeslot.Utils.DocumentValidator
  alias TymeslotWeb.Helpers.FileOperations

  @root "booking_attachments"

  # Long enough that no booking still in flight (payment checkout included)
  # can lose its files, short enough that abandoned uploads don't linger.
  @orphan_grace_hours 24

  # Display names are shown in the dashboard and emails and sent back in a
  # Content-Disposition header; they never reach the file system.
  @max_filename_length 200

  @content_types %{
    "csv" => "text/csv",
    "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "jpeg" => "image/jpeg",
    "jpg" => "image/jpeg",
    "md" => "text/markdown",
    "ods" => "application/vnd.oasis.opendocument.spreadsheet",
    "odt" => "application/vnd.oasis.opendocument.text",
    "pdf" => "application/pdf",
    "png" => "image/png",
    "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "svg" => "image/svg+xml",
    "txt" => "text/plain",
    "webp" => "image/webp",
    "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "zip" => "application/zip"
  }

  @type attachment :: %{String.t() => String.t() | non_neg_integer()}

  @doc """
  File types (lowercase extensions) a booker may attach right now. An empty
  list means the admin has switched attachments off for the whole instance.
  """
  @spec allowed_types() :: [String.t()]
  def allowed_types, do: AppSettings.get(:booking_attachment_types)

  @doc """
  Whether the booking form for `meeting_type` offers the attachment field:
  the host switched it on for this type and the admin allows at least one
  file type.
  """
  @spec enabled_for?(map() | nil) :: boolean()
  def enabled_for?(%{allow_attachments: true}), do: allowed_types() != []
  def enabled_for?(_meeting_type), do: false

  @doc "A fresh batch (relative directory) for one booking submission's files."
  @spec new_batch(pos_integer()) :: String.t()
  def new_batch(organizer_user_id) when is_integer(organizer_user_id) do
    Path.join([@root, Integer.to_string(organizer_user_id), UUID.generate()])
  end

  @doc """
  Moves an uploaded temp file into `batch`, after checking that its content
  matches its extension and that the extension is one of `allowed_types`.
  """
  @spec store(String.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, attachment()} | {:error, :invalid_type | :invalid_content | term()}
  def store(batch, source_path, client_name, allowed_types) do
    extension = extension(client_name)
    id = UUID.generate()
    relative = Path.join(batch, "#{id}.#{extension}")

    with :ok <- check_type(extension, allowed_types),
         :ok <- check_content(source_path, extension),
         {:ok, dest} <- absolute_path(relative),
         :ok <- FileOperations.ensure_secure_directory(Path.dirname(dest)),
         {:ok, _dest} <- FileOperations.atomic_file_move(source_path, dest, %{batch: batch}),
         {:ok, %File.Stat{size: size}} <- File.stat(dest) do
      {:ok,
       %{
         "id" => id,
         "filename" => display_name(client_name),
         "stored_path" => relative,
         "content_type" => Map.fetch!(@content_types, extension),
         "byte_size" => size
       }}
    end
  end

  @doc """
  The attachment `attachment_id` of meeting `meeting_id` with its absolute
  path, for the meeting's organiser only. Anything else — an unknown meeting,
  someone else's meeting, an unknown attachment or a file that is gone — is
  the same `:not_found`, so the answer reveals nothing about what exists.
  """
  @spec fetch_for_organizer(String.t(), String.t(), pos_integer()) ::
          {:ok, attachment(), String.t()} | {:error, :not_found}
  def fetch_for_organizer(meeting_id, attachment_id, organizer_user_id) do
    with {:ok, %{organizer_user_id: ^organizer_user_id} = meeting} <-
           MeetingQueries.get_meeting(meeting_id),
         {:ok, attachment} <- find(meeting, attachment_id),
         {:ok, path} <- absolute_path(attachment),
         true <- File.regular?(path) do
      {:ok, attachment, path}
    else
      _not_available -> {:error, :not_found}
    end
  end

  @doc """
  Absolute path of a stored attachment (or a relative path under the private
  root), refusing anything that would resolve outside it.
  """
  @spec absolute_path(attachment() | String.t()) ::
          {:ok, String.t()} | {:error, :path_traversal_attempt}
  def absolute_path(%{"stored_path" => relative}), do: absolute_path(relative)

  def absolute_path(relative) when is_binary(relative) do
    if Path.type(relative) == :relative and ".." not in Path.split(relative) do
      FileOperations.validate_and_sanitize_path(private_root(), relative)
    else
      {:error, :path_traversal_attempt}
    end
  end

  @doc """
  Deletes the batch the given attachments were stored in. Used when a booking
  that already stored its files fails, and when a meeting is deleted.
  """
  @spec delete_batch([attachment()]) :: :ok
  def delete_batch(attachments) when is_list(attachments) do
    attachments
    |> Enum.map(&Path.dirname(&1["stored_path"]))
    |> Enum.uniq()
    |> Enum.each(&remove_dir/1)
  end

  @doc """
  Deletes every attachment ever uploaded to `organizer_user_id`'s bookings.
  Same contract as `Tymeslot.Profiles.delete_avatar_files/1`, for account
  deletion.
  """
  @spec delete_user_files(pos_integer()) :: :ok | {:error, term(), String.t()}
  def delete_user_files(organizer_user_id) when is_integer(organizer_user_id) do
    dir = Path.join([private_root(), @root, Integer.to_string(organizer_user_id)])

    case File.rm_rf(dir) do
      {:ok, _removed} -> :ok
      {:error, reason, path} -> {:error, reason, path}
    end
  end

  @doc """
  Deletes batches older than #{@orphan_grace_hours} hours that no meeting
  references any more. Returns the number of batches removed.
  """
  @spec prune_orphans() :: non_neg_integer()
  def prune_orphans do
    cutoff = DateTime.to_unix(Clock.utc_now()) - @orphan_grace_hours * 3600
    base = Path.join(private_root(), @root)

    base
    |> list_dir()
    |> Enum.flat_map(&orphaned_batches(base, &1, cutoff))
    |> Enum.map(&remove_dir/1)
    |> length()
  end

  defp find(%{attendee_attachments: attachments}, id) do
    case Enum.find(attachments, &(&1["id"] == id)) do
      nil -> :error
      attachment -> {:ok, attachment}
    end
  end

  defp orphaned_batches(base, user_dir, cutoff) do
    case Integer.parse(user_dir) do
      {user_id, ""} ->
        referenced =
          user_id
          |> MeetingQueries.list_attendee_attachment_paths()
          |> MapSet.new(&Path.dirname/1)

        base
        |> Path.join(user_dir)
        |> list_dir()
        |> Enum.map(&Path.join([@root, user_dir, &1]))
        |> Enum.reject(&MapSet.member?(referenced, &1))
        |> Enum.filter(&older_than?(&1, cutoff))

      _not_a_user_dir ->
        []
    end
  end

  defp older_than?(relative, cutoff) do
    case File.stat(Path.join(private_root(), relative), time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime < cutoff
      {:error, _reason} -> false
    end
  end

  defp list_dir(dir) do
    case File.ls(dir) do
      {:ok, entries} -> entries
      {:error, _reason} -> []
    end
  end

  defp remove_dir(relative) do
    with {:ok, dir} <- absolute_path(relative),
         {:ok, _removed} <- File.rm_rf(dir) do
      :ok
    else
      error ->
        Logger.warning("Could not delete booker attachments",
          batch: relative,
          reason: LogFormat.reason(error)
        )

        :ok
    end
  end

  defp check_type(extension, allowed_types) do
    if extension in allowed_types, do: :ok, else: {:error, :invalid_type}
  end

  defp check_content(path, extension) do
    if DocumentValidator.valid_file?(path, extension), do: :ok, else: {:error, :invalid_content}
  end

  defp extension(client_name) do
    client_name |> Path.extname() |> String.trim_leading(".") |> String.downcase()
  end

  # Keeps the booker's own name (diacritics included) but drops anything that
  # could break a header or a path: directory parts and control characters.
  defp display_name(client_name) do
    name =
      client_name
      |> String.replace("\\", "/")
      |> Path.basename()
      |> String.replace(~r/[\p{Cc}"]/u, "")
      |> String.trim()
      |> String.slice(0, @max_filename_length)

    if name == "", do: "attachment", else: name
  end

  defp private_root do
    Application.get_env(:tymeslot, :private_upload_directory, "private_uploads")
  end
end
