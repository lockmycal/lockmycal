defmodule Tymeslot.Security.AuditLog do
  @moduledoc """
  Persistent audit trail: the events `Tymeslot.Security.SecurityLogger` logs,
  plus payment events recorded through `record_event/2`, kept in
  `audit_events` for `retention_days/0` so they survive the container whose
  stdout the log lines went to, and can be browsed in the admin dashboard.

  Which events are kept is switched per category by an admin
  (`Tymeslot.Security.AuditLog.Catalog`, App Settings → Audit log). Out of the
  box, input-hygiene noise that describes no action by a person — form
  validation results, sanitised or truncated input, bot honeypot hits — stays
  in the text log only.
  `rate_limit_violation` is kept but throttled to one row per minute per IP
  and limit type: during an attack it fires on every request, and one row a
  minute says the same thing.

  Recording never fails the caller. A security event is logged from inside
  login, logout and account flows, a payment event from inside Stripe webhook
  handling; a database problem writing the audit row is logged and swallowed
  rather than turned into a failed login or a webhook Stripe retries.
  """

  require Logger

  alias Tymeslot.AppSettings
  alias Tymeslot.Pagination.OffsetPage
  alias Tymeslot.Security.AuditLog.{AuditEventQueries, AuditEventSchema, Catalog}
  alias Tymeslot.Security.RateLimiter

  @throttled_events ["rate_limit_violation"]
  @throttle_window_ms 60_000
  @max_string_length 500

  @doc """
  Whether events of this type are kept in the audit log, per the admin's
  per-category switches (`Tymeslot.Security.AuditLog.Catalog`).
  """
  @spec recorded?(String.t()) :: boolean()
  def recorded?(event_type) do
    event_type
    |> Catalog.category_for()
    |> Catalog.enabled?(AppSettings.get(:audit_log_events))
  end

  @doc """
  Stores one event. `canonical` is `SecurityLogger`'s canonical map plus the
  unmasked `:email`; `additional_data` goes into `metadata`, reduced to plain
  JSON values.
  """
  @spec record(String.t(), map(), map()) :: :ok
  def record(event_type, canonical, additional_data) do
    if recorded?(event_type) and not throttled?(event_type, canonical) do
      insert(event_type, canonical, additional_data)
    end

    :ok
  end

  @doc """
  Stores an event that is not a security event, so it has no
  `SecurityLogger` log line of its own (payments log theirs where they
  happen). `attrs` takes `:user_id` (the account the event is about),
  `:actor_user_id` and `:metadata`. Honours the same per-category switches
  as `record/3`.
  """
  @spec record_event(String.t(), map()) :: :ok
  def record_event(event_type, attrs) do
    record(
      event_type,
      Map.take(attrs, [:user_id, :actor_user_id]),
      Map.get(attrs, :metadata, %{})
    )
  end

  defp throttled?(event_type, canonical) when event_type in @throttled_events do
    key = "audit:#{event_type}:#{canonical[:ip_address]}:#{canonical[:limit_type]}"

    match?({:deny, _limit}, RateLimiter.check_rate(key, @throttle_window_ms, 1))
  end

  defp throttled?(_event_type, _canonical), do: false

  defp insert(event_type, canonical, additional_data) do
    metadata =
      (additional_data || %{})
      |> Map.merge(Map.take(canonical, [:lockout_type, :limit_type]))
      |> jsonable_map()

    attrs =
      canonical
      |> Map.take([
        :user_id,
        :actor_user_id,
        :email,
        :email_masked,
        :ip_address,
        :user_agent,
        :session_id,
        :provider
      ])
      |> Map.update(:email, nil, &truncate(&1, 255))
      |> Map.update(:ip_address, nil, &to_text/1)
      |> Map.update(:user_agent, nil, &truncate(&1, 200))
      |> Map.merge(%{event_type: event_type, metadata: metadata})

    case AuditEventQueries.insert(attrs) do
      {:ok, _event} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Could not store security audit event",
          event_type: event_type,
          errors: inspect(changeset.errors)
        )
    end
  rescue
    error ->
      Logger.warning("Could not store security audit event",
        event_type: event_type,
        error: Exception.message(error)
      )
  end

  defp jsonable_map(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), jsonable(value)} end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp jsonable(value) when is_binary(value), do: truncate(value, @max_string_length)
  defp jsonable(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp jsonable(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)
  defp jsonable(value) when is_map(value) and not is_struct(value), do: jsonable_map(value)
  defp jsonable(value), do: truncate(inspect(value), @max_string_length)

  defp to_text(nil), do: nil
  defp to_text(value) when is_binary(value), do: truncate(value, 64)
  defp to_text(value) when is_tuple(value), do: value |> :inet.ntoa() |> to_string()
  defp to_text(value), do: truncate(inspect(value), 64)

  defp truncate(nil, _max), do: nil
  defp truncate(value, max) when is_binary(value), do: String.slice(value, 0, max)
  defp truncate(value, max), do: truncate(inspect(value), max)

  @doc """
  One page of events, newest first (`Tymeslot.Pagination.OffsetPage`).
  `filters` takes `:event_type`, `:category`, `:user_ids`, `:from` and `:to`
  (see `AuditEventQueries.list/3`).
  """
  @spec list_events(map(), integer(), integer()) :: OffsetPage.t(AuditEventSchema.t())
  def list_events(filters, page \\ 1, per_page \\ OffsetPage.default_page_size()) do
    filters
    |> AuditEventQueries.count()
    |> OffsetPage.fetch(page, per_page, &AuditEventQueries.list(filters, &1, &2))
  end

  @doc """
  Every event type the admin filter offers, grouped by `Catalog` category in
  its order: the types a category is known to produce plus any already in the
  log (dynamically named ones such as `<form>_validation_failure`).
  """
  @spec event_types_by_category() :: [{String.t(), [String.t()]}]
  def event_types_by_category do
    logged = Enum.group_by(AuditEventQueries.event_types(), &Catalog.category_for/1)

    Enum.map(Catalog.keys(), fn key ->
      types = Catalog.known_event_types(key) ++ Map.get(logged, key, [])
      {key, types |> Enum.uniq() |> Enum.sort()}
    end)
  end

  @doc """
  How many days events are kept: the admin setting, else
  `AUDIT_LOG_RETENTION_DAYS`, else 90.
  """
  @spec retention_days() :: pos_integer()
  def retention_days, do: AppSettings.get(:audit_log_retention_days)

  @doc "Deletes events older than the retention period. Returns how many."
  @spec prune(DateTime.t()) :: non_neg_integer()
  def prune(%DateTime{} = now) do
    {deleted, nil} = AuditEventQueries.delete_older_than(retention_days(), now)
    deleted
  end
end
