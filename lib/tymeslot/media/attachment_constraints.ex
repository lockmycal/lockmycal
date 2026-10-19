defmodule Tymeslot.Media.AttachmentConstraints do
  @moduledoc """
  The limits on the files a booker attaches to a booking, all three from admin
  settings: the accepted types (`:booking_attachment_types`, an empty list
  switching the feature off instance-wide), the per-file size and the number of
  files. Kept apart from `Tymeslot.Media.UploadConstraints`, which modules read
  at compile time and which must therefore not depend on `Tymeslot.AppSettings`.
  """

  alias Tymeslot.AppSettings

  @bytes_per_mb 1_000_000

  @doc "The accepted file extensions (lowercase, with the dot)."
  @spec allowed_extensions() :: [String.t()]
  def allowed_extensions, do: Enum.map(AppSettings.get(:booking_attachment_types), &("." <> &1))

  @doc "The maximum size of one file, in bytes."
  @spec max_file_size() :: pos_integer()
  def max_file_size, do: AppSettings.get(:max_booking_attachment_size_mb) * @bytes_per_mb

  @doc "The maximum number of files a booker may attach to one booking."
  @spec max_entries() :: pos_integer()
  def max_entries, do: AppSettings.get(:max_booking_attachments)
end
