defmodule Tymeslot.Profiles.BrandLogo do
  @moduledoc """
  The organizer's own logo: shown instead of the app logo in the top bar of
  their public pages and at the head of the emails about their meetings.

  Gated by the `:custom_branding_allowed` feature (`Tymeslot.Features`). Core
  allows it to everyone; SaaS restricts it to paid plans. The gate is applied
  when the logo is *shown*, not only when it is stored, so after a downgrade
  the file stays on disk and simply stops appearing — an upgrade brings it
  back without a new upload.

  Storage follows `Tymeslot.Emails.Branding`: the dashboard rasterises the
  picked image to PNG in the browser (every mail client renders PNG), the
  server re-validates it, and the file lands under
  `<upload_dir>/branding/profiles/<profile_id>/` with a random suffix so a
  replacement is never hidden by a cached image. Only the path relative to the
  upload directory is stored.
  """

  alias Tymeslot.Features
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Profiles.ProfileSchema
  alias Tymeslot.Utils.MediaValidator
  alias TymeslotWeb.Helpers.FileOperations
  alias TymeslotWeb.Helpers.UploadHandler

  require Logger

  @feature :custom_branding_allowed
  @random_suffix_bytes 8

  @doc "The feature flag that gates the organizer logo."
  @spec feature() :: atom()
  def feature, do: @feature

  @doc "Whether the profile's owner may set and show their own logo."
  @spec allowed?(ProfileSchema.t() | nil) :: boolean()
  def allowed?(%ProfileSchema{user_id: user_id}) when is_integer(user_id),
    do: Features.check_access(user_id, @feature) == :ok

  def allowed?(_profile), do: false

  @doc """
  Stores the PNG at `source_path` as the profile's logo, replacing and
  deleting any logo stored before.
  """
  @spec store(ProfileSchema.t(), String.t()) ::
          {:ok, ProfileSchema.t()} | {:error, :not_allowed | :not_a_png | atom()}
  def store(%ProfileSchema{} = profile, source_path) when is_binary(source_path) do
    with {:allowed, true} <- {:allowed, allowed?(profile)},
         true <- MediaValidator.valid_png_file?(source_path),
         {:ok, relative} <- write_logo(profile, source_path),
         {:ok, updated} <- update_path(profile, relative) do
      delete_stored(profile.brand_logo_path)
      {:ok, updated}
    else
      {:allowed, false} -> {:error, :not_allowed}
      false -> {:error, :not_a_png}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Clears the profile's logo and deletes the stored file."
  @spec remove(ProfileSchema.t()) :: {:ok, ProfileSchema.t()} | {:error, atom()}
  def remove(%ProfileSchema{} = profile) do
    case update_path(profile, nil) do
      {:ok, updated} ->
        delete_stored(profile.brand_logo_path)
        {:ok, updated}

      error ->
        error
    end
  end

  @doc """
  URL path of the stored logo for the dashboard preview, or `nil` when none is
  stored or the file is gone. Not gated: the owner sees what is stored even
  while their plan does not show it.
  """
  @spec url(ProfileSchema.t() | nil) :: String.t() | nil
  def url(profile) do
    case stored_relative_path(profile) do
      nil -> nil
      relative -> "/uploads/" <> relative
    end
  end

  @doc """
  URL path of the logo to show on the profile's public pages, or `nil` when the
  app logo applies (no logo stored, or the feature is not allowed).
  """
  @spec display_url(ProfileSchema.t() | nil) :: String.t() | nil
  def display_url(profile) do
    with url when is_binary(url) <- url(profile),
         true <- allowed?(profile) do
      url
    else
      _no_logo -> nil
    end
  end

  @doc """
  PNG bytes of the logo to attach to an email about the profile's meetings, or
  `:error` when the instance logo applies instead.
  """
  @spec email_logo_bytes(ProfileSchema.t() | nil) :: {:ok, binary()} | :error
  def email_logo_bytes(profile) do
    with relative when is_binary(relative) <- stored_relative_path(profile),
         true <- allowed?(profile),
         {:ok, bytes} <- File.read(Path.join(upload_dir(), relative)) do
      {:ok, bytes}
    else
      _no_logo -> :error
    end
  end

  @doc """
  Removes every logo file stored for a profile. For erasing a profile that no
  longer exists: it touches no database row.
  """
  @spec delete_all_files(pos_integer()) :: :ok | {:error, File.posix(), Path.t()}
  def delete_all_files(profile_id) when is_integer(profile_id) do
    case File.rm_rf(profile_dir(profile_id)) do
      {:ok, _removed} -> :ok
      {:error, reason, failed_path} -> {:error, reason, failed_path}
    end
  end

  defp stored_relative_path(%ProfileSchema{brand_logo_path: relative})
       when is_binary(relative) do
    if File.regular?(Path.join(upload_dir(), relative)), do: relative, else: nil
  end

  defp stored_relative_path(_profile), do: nil

  defp update_path(profile, path) do
    case ProfileQueries.update_brand_logo_path(profile, path) do
      {:ok, updated} -> {:ok, updated}
      {:error, %Ecto.Changeset{}} -> {:error, :invalid_path}
    end
  end

  defp write_logo(profile, source_path) do
    case UploadHandler.store_file_atomically(
           source_path,
           profile_dir(profile.id),
           random_filename(),
           %{context: :brand_logo, profile_id: profile.id}
         ) do
      {:ok, filename} ->
        {:ok, Path.join(relative_dir(profile.id), filename)}

      {:error, reason} ->
        Logger.error("Failed to store organizer logo",
          profile_id: profile.id,
          reason: LogFormat.reason(reason)
        )

        {:error, :write_failed}
    end
  end

  defp delete_stored(nil), do: :ok

  defp delete_stored(relative) do
    FileOperations.safe_delete_file(Path.join(upload_dir(), relative), %{context: :brand_logo})
  end

  defp relative_dir(profile_id), do: Path.join(["branding", "profiles", to_string(profile_id)])

  defp profile_dir(profile_id), do: Path.join(upload_dir(), relative_dir(profile_id))

  defp random_filename do
    suffix =
      @random_suffix_bytes
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)

    "logo-#{suffix}.png"
  end

  defp upload_dir, do: Application.get_env(:tymeslot, :upload_directory, "uploads")
end
