defmodule Tymeslot.Workers.AuditLogPruneWorker do
  @moduledoc """
  Daily deletion of security audit events older than the retention period
  (`Tymeslot.Security.AuditLog.retention_days/0`). The events hold IP
  addresses and user agents, so they must not be kept indefinitely.
  """

  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 60]
  require Logger

  alias Tymeslot.Security.AuditLog

  @impl Oban.Worker
  def perform(_job) do
    deleted = AuditLog.prune(DateTime.utc_now())

    Logger.info("Audit log prune completed",
      deleted_count: deleted,
      retention_days: AuditLog.retention_days()
    )

    :ok
  rescue
    error ->
      Logger.error("Audit log prune failed", error: Exception.message(error))
      {:error, Exception.message(error)}
  end
end
