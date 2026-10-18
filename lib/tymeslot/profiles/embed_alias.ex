defmodule Tymeslot.Profiles.EmbedAlias do
  @moduledoc """
  The booking widget's alias: a secret handle that stands in for the username
  in the widget's URLs (`/<alias>`, `/<alias>/<slug>`), so the snippet on the
  embedding site does not give away the organiser's public booking page.

  An alias is `_` followed by a random token. A username must start with a
  letter or digit (`UsernameValidator`), so an alias can never collide with
  one and the first character alone says which of the two a path segment is.

  Through an alias the page shows only what the widget may show
  (`Tymeslot.MeetingTypes.reachable_via_alias?/1`): the overview lists the `show_in_embed` types, and a direct
  slug reaches a type that is private or shown in the widget. A type that is
  only on the public page stays out of reach, or the alias would hide nothing.

  Generating or clearing an alias is gated by the `:embed_alias_allowed`
  feature (`Tymeslot.Features.check_access/2`), the same way a custom
  username is.
  """

  alias Tymeslot.Features
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Profiles.ProfileSchema

  @prefix "_"

  @doc "Whether a booking path segment is an alias rather than a username."
  @spec alias?(String.t() | nil) :: boolean()
  def alias?(@prefix <> _token), do: true
  def alias?(_handle), do: false

  @doc """
  Whether an app URL (e.g. a meeting's stored `view_url`) is under an alias:
  its first path segment is one. A booking made through the widget's hidden
  address stores its links that way.
  """
  @spec url_under_alias?(String.t() | nil) :: boolean()
  def url_under_alias?(url) when is_binary(url) do
    case url |> URI.parse() |> Map.get(:path) |> to_string() |> String.split("/", trim: true) do
      [handle | _rest] -> alias?(handle)
      [] -> false
    end
  end

  def url_under_alias?(_url), do: false

  @doc """
  The profile a booking path segment names: by alias when it is one, by
  username otherwise. Returns `nil` when there is none.
  """
  @spec get_profile_by_handle(String.t()) :: ProfileSchema.t() | nil
  def get_profile_by_handle(handle) when is_binary(handle) do
    case get_by_handle_with_user(handle) do
      {:ok, profile} -> profile
      {:error, :not_found} -> nil
    end
  end

  @doc "Like `get_profile_by_handle/1`, as a tagged tuple with the user preloaded."
  @spec get_by_handle_with_user(String.t()) :: {:ok, ProfileSchema.t()} | {:error, :not_found}
  def get_by_handle_with_user(handle) when is_binary(handle) do
    if alias?(handle),
      do: ProfileQueries.get_by_embed_alias_with_user(handle),
      else: ProfileQueries.get_by_username_with_user(handle)
  end

  @doc """
  Gives the profile a new random alias, replacing (and so disabling) any
  previous one.
  """
  @spec generate(ProfileSchema.t()) ::
          {:ok, ProfileSchema.t()} | {:error, Features.access_error() | Ecto.Changeset.t()}
  def generate(%ProfileSchema{} = profile) do
    with :ok <- Features.check_access(profile.user_id, :embed_alias_allowed) do
      ProfileQueries.update_embed_alias(profile, unused_alias())
    end
  end

  @doc "Removes the profile's alias, so its widget URLs stop working."
  @spec clear(ProfileSchema.t()) ::
          {:ok, ProfileSchema.t()} | {:error, Features.access_error() | Ecto.Changeset.t()}
  def clear(%ProfileSchema{} = profile) do
    with :ok <- Features.check_access(profile.user_id, :embed_alias_allowed) do
      ProfileQueries.update_embed_alias(profile, nil)
    end
  end

  @doc """
  Removes the profile's alias without the `:embed_alias_allowed` gate.

  System use only (e.g. when the owner's plan no longer includes the alias):
  a user-initiated clear goes through `clear/1` so the gate applies to it.
  """
  @spec reset(ProfileSchema.t()) :: {:ok, ProfileSchema.t()} | {:error, Ecto.Changeset.t()}
  def reset(%ProfileSchema{} = profile), do: ProfileQueries.update_embed_alias(profile, nil)

  # 10 random bytes, base32: 16 characters, far beyond enumeration. The check
  # is a safety net; the unique index is what guarantees uniqueness.
  defp unused_alias do
    Enum.find(Stream.repeatedly(&random_alias/0), &(not ProfileQueries.embed_alias_taken?(&1)))
  end

  defp random_alias do
    @prefix <> (10 |> :crypto.strong_rand_bytes() |> Base.encode32(case: :lower, padding: false))
  end
end
