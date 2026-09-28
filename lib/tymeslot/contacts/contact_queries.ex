defmodule Tymeslot.Contacts.ContactQueries do
  @moduledoc """
  Database queries for contacts. The only module in this domain allowed to
  call `Repo` directly (`CredoChecks.RepoCallBoundary`).
  """

  import Ecto.Query, warn: false

  alias Tymeslot.Contacts.ContactSchema
  alias Tymeslot.Repo
  alias Tymeslot.Utils.LikeEscape

  @doc """
  Lists contacts for an organizer by name (then id, so pages of equal names
  never overlap). `opts[:search]` filters by a case-insensitive match
  against name or email; `opts[:limit]` caps the result at the database
  rather than fetching every matching row, and `opts[:offset]` skips that
  many first.
  """
  @spec list_contacts(integer(), keyword()) :: [ContactSchema.t()]
  def list_contacts(organizer_user_id, opts \\ []) do
    organizer_user_id
    |> matching(Keyword.get(opts, :search))
    |> order_by([c], asc: c.name, asc: c.id)
    |> apply_limit(Keyword.get(opts, :limit))
    |> apply_offset(Keyword.get(opts, :offset))
    |> Repo.all()
  end

  @doc "How many contacts `list_contacts/2` finds for `search` (without a limit)."
  @spec count_contacts(integer(), String.t() | nil) :: non_neg_integer()
  def count_contacts(organizer_user_id, search) do
    organizer_user_id
    |> matching(search)
    |> Repo.aggregate(:count, :id)
  end

  defp matching(organizer_user_id, search) do
    ContactSchema
    |> where([c], c.organizer_user_id == ^organizer_user_id)
    |> apply_search(search)
  end

  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)

  defp apply_offset(query, nil), do: query

  defp apply_offset(query, offset) when is_integer(offset) and offset >= 0,
    do: offset(query, ^offset)

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    term = "%" <> LikeEscape.escape(search) <> "%"

    where(
      query,
      [c],
      ilike(c.name, ^term) or ilike(c.email, ^term)
    )
  end

  @doc """
  Gets a single contact by ID for a specific organizer.
  """
  @spec get_contact(integer(), integer()) :: {:ok, ContactSchema.t()} | {:error, :not_found}
  def get_contact(id, organizer_user_id) do
    case Repo.get_by(ContactSchema, id: id, organizer_user_id: organizer_user_id) do
      nil -> {:error, :not_found}
      contact -> {:ok, contact}
    end
  end

  @doc """
  Creates a contact.
  """
  @spec insert_contact(map()) :: {:ok, ContactSchema.t()} | {:error, Ecto.Changeset.t()}
  def insert_contact(attrs) do
    %ContactSchema{}
    |> ContactSchema.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a contact.
  """
  @spec update_contact(ContactSchema.t(), map()) ::
          {:ok, ContactSchema.t()} | {:error, Ecto.Changeset.t()}
  def update_contact(%ContactSchema{} = contact, attrs) do
    contact
    |> ContactSchema.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a contact.
  """
  @spec delete_contact(ContactSchema.t()) ::
          {:ok, ContactSchema.t()} | {:error, Ecto.Changeset.t()}
  def delete_contact(%ContactSchema{} = contact) do
    Repo.delete(contact)
  end

  @doc """
  Upserts a contact from a new public booking: creates the row if the
  organizer has no contact with this email yet, otherwise refreshes
  `name`/`phone`/`company` on the existing one. `:email` (the conflict
  target) and `:note` (owned by the organizer, never overwritten by an
  automatic capture) are deliberately never replaced.

  `returning: true` matters here beyond the usual "get the id back": on a
  conflict, the fields this upsert deliberately never replaces (`:note`)
  would otherwise come back as the blank defaults of the just-built struct
  rather than the row's actual persisted value.
  """
  @spec upsert_contact_from_booking(integer(), map()) ::
          {:ok, ContactSchema.t()} | {:error, Ecto.Changeset.t()}
  def upsert_contact_from_booking(organizer_user_id, attrs) do
    %ContactSchema{organizer_user_id: organizer_user_id}
    |> ContactSchema.capture_changeset(Map.put(attrs, :organizer_user_id, organizer_user_id))
    |> Repo.insert(
      on_conflict: {:replace, [:name, :phone, :company, :updated_at]},
      conflict_target: [:organizer_user_id, :email],
      returning: true
    )
  end
end
