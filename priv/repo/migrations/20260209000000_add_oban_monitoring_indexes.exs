defmodule Tymeslot.Repo.Migrations.AddObanMonitoringIndexes do
  @moduledoc """
  Creates performance indexes for Oban queue monitoring and health check features.

  These indexes are required for optimal performance of:
  - ObanQueueMonitorWorker: Uses group_by queries on state, queue, and timestamps
  - HealthCheck duplicate detection: Uses JSONB fragment queries on args field

  Without these indexes, queries may be slow or timeout on large job tables (>10k jobs).
  The CONCURRENTLY option allows index creation without locking the table for writes.
  """

  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Index for ObanQueueMonitorWorker group_by queries
    # Supports efficient queries that group jobs by state and queue
    # The partial index (WHERE clause) reduces index size by only indexing relevant states
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_oban_jobs_monitoring
      ON oban_jobs (state, queue, inserted_at)
      WHERE state IN ('available', 'retryable')
    """

    # Additional index for retryable job monitoring with scheduled_at
    # Supports queries that check if retryable jobs are past their retry time
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_oban_jobs_scheduled_monitoring
      ON oban_jobs (state, queue, scheduled_at, inserted_at)
      WHERE state = 'retryable'
    """

    # GIN index for JSONB args field used in duplicate detection
    # Supports efficient queries on JSON fields like args->>'integration_id'
    # GIN indexes are ideal for JSONB containment and field extraction queries
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_oban_jobs_args_gin
      ON oban_jobs USING gin (args)
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_oban_jobs_monitoring"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_oban_jobs_scheduled_monitoring"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_oban_jobs_args_gin"
  end
end
