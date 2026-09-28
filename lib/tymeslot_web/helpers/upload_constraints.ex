defmodule TymeslotWeb.Helpers.UploadConstraints do
  @moduledoc """
  Centralized upload constraints for allowed file extensions and maximum sizes.
  Use these helpers in LiveView allow_upload, file validation, and storage layers
  to keep limits consistent and avoid drift.

  The image/video limits (theme background customization only) are
  admin-configurable via `Tymeslot.AppSettings` (`:max_image_upload_size_mb`
  / `:max_video_upload_size_mb`), projected into
  `Application.get_env(:tymeslot, :uploads)` the same way every other
  `AppSettings`-backed value is read at its call site (see that module's
  moduledoc). The avatar limit is a fixed constant, not admin-configurable.
  """

  @type upload_type :: :avatar | :image | :video

  @bytes_per_mb 1_000_000

  # Fixed, not admin-configurable.
  @avatar_max_size 300_000

  # Built-in defaults (MB) used when no admin override or config value is
  # set for the image/video limits.
  @default_image_max_mb 20
  @default_video_max_mb 100

  # Allowed extensions per type
  @extensions %{
    avatar: [".jpg", ".jpeg", ".png", ".gif", ".webp"],
    image: [".jpg", ".jpeg", ".png", ".webp"],
    video: [".mp4", ".webm", ".mov"]
  }

  @doc """
  Returns the allowed file extensions (lowercase) for a given upload type.
  """
  @spec allowed_extensions(upload_type) :: [String.t()]
  def allowed_extensions(type) when type in [:avatar, :image, :video] do
    Map.fetch!(@extensions, type)
  end

  @doc """
  Returns the maximum file size (in bytes) for a given upload type. Avatar is
  a fixed constant; image/video read the current admin-configurable setting
  (falling back to their built-in defaults).
  """
  @spec max_file_size(upload_type) :: pos_integer()
  def max_file_size(:avatar), do: @avatar_max_size

  def max_file_size(:image) do
    uploads_config() |> Keyword.get(:max_image_size_mb, @default_image_max_mb) |> mb_to_bytes()
  end

  def max_file_size(:video) do
    uploads_config() |> Keyword.get(:max_video_size_mb, @default_video_max_mb) |> mb_to_bytes()
  end

  defp uploads_config, do: Application.get_env(:tymeslot, :uploads, [])

  defp mb_to_bytes(mb), do: mb * @bytes_per_mb
end
