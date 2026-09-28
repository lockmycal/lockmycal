defmodule Tymeslot.Security.AuditLog.AuditEventQueries do
  @moduledoc """
  Queries over `audit_events`. All `Repo.*` calls for the audit log live here
  per the `CredoChecks.RepoCallBoundary` rule.
  """
  import Ecto.Query

  alias Tymeslot.Infrastructure.BatchDeleteQueries
  alias Tymeslot.Repo
  alias Tymeslot.Security.AuditLog.AuditEventSchema
  alias Tymeslot.Security.AuditLog.Catalog

  @spec insert(map()) :: {:ok, AuditEventSchema.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    %AuditEventSchema{} |> AuditEventSchema.changeset(attrs) |> Repo.insert()
  end

  @doc """
  Lists `limit` events newest first, skipping the first `offset`. Filters:

    * `:event_type` — exact match
    * `:category` — every event type of a `Catalog` category
    * `:user_ids` — events about, or caused by, any of these users
    * `:from` / `:to` — `inserted_at` at or after `:from`, before `:to`
  """
  @spec list(map(), pos_integer(), non_neg_integer()) :: [AuditEventSchema.t()]
  def list(filters, limit, offset) do
    filters
    |> filtered()
    |> order_by([e], desc: e.id)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "How many events match `filters` (same keys as `list/3`)."
  @spec count(map()) :: non_neg_integer()
  def count(filters), do: filters |> filtered() |> Repo.aggregate(:count)

  defp filtered(filters) do
    AuditEventSchema
    |> filter_event_type(filters[:event_type])
    |> filter_category(filters[:category])
    |> filter_user_ids(filters[:user_ids])
    |> filter_from(filters[:from])
    |> filter_to(filters[:to])
  end

  defp filter_event_type(query, type) when is_binary(type) and type != "",
    do: where(query, [e], e.event_type == ^type)

  defp filter_event_type(query, _type), do: query

  defp filter_category(query, key) when is_binary(key) and key != "" do
    case Catalog.matcher(key) do
      {:match, patterns} ->
        where(query, ^matches(patterns))

      {:none_of, all_patterns} ->
        Enum.reduce(all_patterns, query, fn patterns, acc ->
          where(acc, ^dynamic([e], not (^matches(patterns))))
        end)
    end
  end

  defp filter_category(query, _key), do: query

  # Mirrors `Catalog.category_for/1` in SQL: any exact name, prefix, suffix
  # or infix. No patterns at all match nothing.
  defp matches(patterns) do
    exact = Map.get(patterns, :exact, [])

    likes =
      Enum.map(Map.get(patterns, :prefixes, []), &(escape_like(&1) <> "%")) ++
        Enum.map(Map.get(patterns, :suffixes, []), &("%" <> escape_like(&1))) ++
        Enum.map(Map.get(patterns, :contains, []), &("%" <> escape_like(&1) <> "%"))

    Enum.reduce(likes, dynamic([e], e.event_type in ^exact), fn pattern, acc ->
      dynamic([e], ^acc or like(e.event_type, ^pattern))
    end)
  end

  # `_` is a LIKE wildcard and every event type is full of them.
  defp escape_like(text), do: String.replace(text, ~r/[\\%_]/, "\\\\\\0")

  defp filter_from(query, %DateTime{} = from), do: where(query, [e], e.inserted_at >= ^from)
  defp filter_from(query, _from), do: query

  defp filter_to(query, %DateTime{} = to), do: where(query, [e], e.inserted_at < ^to)
  defp filter_to(query, _to), do: query

  defp filter_user_ids(query, ids) when is_list(ids),
    do: where(query, [e], e.user_id in ^ids or e.actor_user_id in ^ids)

  defp filter_user_ids(query, _ids), do: query

  @doc "The distinct event types present in the log, alphabetically."
  @spec event_types() :: [String.t()]
  def event_types do
    AuditEventSchema
    |> distinct(true)
    |> select([e], e.event_type)
    |> order_by([e], asc: e.event_type)
    |> Repo.all()
  end

  @doc """
  Deletes events older than `days` in bounded batches. A zero, negative or
  non-integer retention is a no-op, so a misconfigured value can never wipe
  the whole table.
  """
  @spec delete_older_than(integer(), DateTime.t()) :: {non_neg_integer(), nil}
  def delete_older_than(days, %DateTime{} = now) when is_integer(days) and days > 0 do
    cutoff = DateTime.add(now, -days, :day)
    BatchDeleteQueries.delete_older_than(AuditEventSchema, :inserted_at, cutoff)
  end

  def delete_older_than(_days, _now), do: {0, nil}
end
