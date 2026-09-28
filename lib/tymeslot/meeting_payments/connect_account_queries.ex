defmodule Tymeslot.MeetingPayments.ConnectAccountQueries do
  @moduledoc """
  All Repo.* calls for connect_accounts.
  """

  import Ecto.Query
  alias Tymeslot.MeetingPayments.ConnectAccountSchema
  alias Tymeslot.Repo

  @spec get(Ecto.UUID.t()) :: ConnectAccountSchema.t() | nil
  def get(id), do: Repo.get(ConnectAccountSchema, id)

  @spec live_for_user(integer()) :: ConnectAccountSchema.t() | nil
  def live_for_user(user_id) do
    Repo.one(
      from c in ConnectAccountSchema,
        where: c.user_id == ^user_id and is_nil(c.deleted_at),
        limit: 1
    )
  end

  @doc """
  Returns the live (non-deleted) Connect accounts for a batch of users, keyed
  by `user_id`. Used where a list of users is rendered alongside their
  Connect account (e.g. the admin Users table) to avoid one query per row.
  """
  @spec live_for_users([integer()]) :: %{integer() => ConnectAccountSchema.t()}
  def live_for_users(user_ids) do
    query =
      from c in ConnectAccountSchema,
        where: c.user_id in ^user_ids and is_nil(c.deleted_at)

    Map.new(Repo.all(query), &{&1.user_id, &1})
  end

  @spec by_stripe_account_id(String.t()) :: ConnectAccountSchema.t() | nil
  def by_stripe_account_id(stripe_account_id) do
    Repo.one(
      from c in ConnectAccountSchema,
        where: c.stripe_account_id == ^stripe_account_id and is_nil(c.deleted_at),
        limit: 1
    )
  end

  @spec insert_placeholder(integer(), String.t()) ::
          {:ok, ConnectAccountSchema.t()} | {:error, Ecto.Changeset.t()}
  def insert_placeholder(user_id, country) do
    %ConnectAccountSchema{}
    |> ConnectAccountSchema.changeset(%{
      user_id: user_id,
      country: country,
      status: "creating"
    })
    |> Repo.insert()
  end

  @spec update(ConnectAccountSchema.t(), map()) ::
          {:ok, ConnectAccountSchema.t()} | {:error, Ecto.Changeset.t()}
  def update(schema, attrs) do
    schema
    |> ConnectAccountSchema.changeset(attrs)
    |> Repo.update()
  end

  @spec delete(ConnectAccountSchema.t()) ::
          {:ok, ConnectAccountSchema.t()} | {:error, Ecto.Changeset.t()}
  def delete(schema), do: Repo.delete(schema)

  @spec soft_delete_for_user(integer(), DateTime.t()) :: {non_neg_integer(), nil}
  def soft_delete_for_user(user_id, now) do
    query =
      from(c in ConnectAccountSchema,
        where: c.user_id == ^user_id and is_nil(c.deleted_at)
      )

    Repo.update_all(query,
      set: [
        deleted_at: now,
        charges_enabled: false,
        status: "deleted",
        user_id: nil,
        updated_at: now
      ]
    )
  end
end
