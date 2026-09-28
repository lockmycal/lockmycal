defmodule Tymeslot.Infrastructure.DashboardCache do
  @moduledoc """
  ETS-based cache for dashboard data using the shared CacheStore.
  """
  use Tymeslot.Infrastructure.CacheStore,
    table_name: :dashboard_cache,
    default_ttl: :timer.minutes(5),
    cleanup_interval: :timer.minutes(10)

  @doc """
  Cache key helpers for consistent key generation.
  """
  @spec integration_status_key(integer()) :: {atom(), integer()}
  def integration_status_key(user_id), do: {:integration_status, user_id}
end
