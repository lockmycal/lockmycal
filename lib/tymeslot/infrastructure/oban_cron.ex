defmodule Tymeslot.Infrastructure.ObanCron do
  @moduledoc """
  Builds and checks the `:cron` section of the Oban configuration.

  `build/1` merges Core's own scheduled workers (declared under `:oban_cron`)
  with any a wrapper application adds via the `:oban_additional_cron`
  extension point — mirroring `Tymeslot.Infrastructure.ObanQueues`'s
  `:oban_queues`/`:oban_additional_queues` pair for `:queues`. Both are read
  at runtime (inside `oban_config/0`, after every config file — including a
  wrapper app's own runtime.exs — has already run), not written directly
  into `config :tymeslot, Oban, cron: [...]` at config time, because
  Elixir's config merge cannot append to a plain list of
  `{cron_string, worker}` tuples — it can only replace it outright, which
  would silently drop Core's own crontab entries if a wrapper app tried to
  extend `:cron` the naive way `:oban_additional_queues` extends `:queues`.
  See the comment on `config :tymeslot, Oban` in config/runtime.exs and
  config/dev.exs.

  `missing_workers/1`/`warn_on_missing_workers/1` check the *built* `:cron`
  section (after `build/1` has run) for the maintenance workers the system
  depends on: `Tymeslot.Workers.ObanMaintenanceWorker`,
  `Tymeslot.Workers.ObanQueueMonitorWorker`,
  `Tymeslot.Workers.ErrorTrackerMaintenanceWorker` and
  `Tymeslot.Workers.AdminAlertDigestWorker` run from the crontab and nowhere
  else. Without them jobs accumulate, queue problems go unreported, stored
  errors are never resolved or pruned, and info alerts never reach the
  operator. Nothing else notices they are gone, so startup says so loudly
  rather than degrading in silence.

  The check reads the raw application environment rather than Oban's own
  normalised state, so it has to know the shapes `:cron` accepts: a keyword
  list, a `{module, opts}` tuple, a bare module, or `false` to disable the
  service outright. Only the first two can carry a crontab of ours.
  """

  alias Tymeslot.Infrastructure.Logging.LogFormat

  require Logger

  @critical_workers [
    Tymeslot.Workers.ObanMaintenanceWorker,
    Tymeslot.Workers.ObanQueueMonitorWorker,
    Tymeslot.Workers.ErrorTrackerMaintenanceWorker,
    Tymeslot.Workers.AdminAlertDigestWorker
  ]

  @doc """
  Returns `base_config` with a merged `:cron` (`[crontab: entries]`) key,
  read from the `:oban_cron`/`:oban_additional_cron` application config.
  """
  @spec build(keyword()) :: keyword()
  def build(base_config) do
    base_cron = Application.get_env(:tymeslot, :oban_cron, [])
    additional_cron = Application.get_env(:tymeslot, :oban_additional_cron, [])

    Keyword.put(base_config, :cron, crontab: merge(base_cron, additional_cron))
  end

  @doc """
  Concatenates `base_cron` and `additional_cron` into one crontab.

  Order carries no meaning for Oban's cron scheduler, so unlike
  `ObanQueues.merge/3` there is no override-by-key semantic to apply here,
  and no reason to detect conflicts between the two lists — a wrapper app's
  entries simply run alongside Core's.
  """
  @spec merge(list(), list()) :: list()
  def merge(base_cron, additional_cron) do
    validate_entries!(base_cron, :oban_cron)
    validate_entries!(additional_cron, :oban_additional_cron)

    base_cron ++ additional_cron
  end

  @doc """
  The critical workers `oban_config` fails to schedule.

  `:no_crontab` means the `:cron` service itself is absent or disabled, which
  costs every critical worker at once and is worth reporting as its own thing.
  """
  @spec missing_workers(keyword()) :: [module()] | :no_crontab
  def missing_workers(oban_config) do
    case crontab(Keyword.get(oban_config, :cron)) do
      nil -> :no_crontab
      crontab -> Enum.reject(@critical_workers, &scheduled?(crontab, &1))
    end
  end

  @doc """
  Logs a warning for each critical worker `oban_config` does not schedule.
  """
  @spec warn_on_missing_workers(keyword()) :: :ok
  def warn_on_missing_workers(oban_config) do
    oban_config
    |> missing_workers()
    |> warn()
  end

  @spec validate_entries!(term(), atom()) :: :ok
  defp validate_entries!(entries, key) do
    unless is_list(entries) and Enum.all?(entries, &valid_entry?/1) do
      raise ArgumentError,
            ":#{key} must be a list of {cron_string, worker} or " <>
              "{cron_string, worker, opts} tuples, got: #{inspect(entries)}"
    end

    :ok
  end

  defp valid_entry?({cron, worker}), do: is_binary(cron) and is_atom(worker)

  defp valid_entry?({cron, worker, opts}),
    do: is_binary(cron) and is_atom(worker) and is_list(opts)

  defp valid_entry?(_other), do: false

  defp warn(:no_crontab) do
    Logger.warning(
      """
      OBAN CRON SERVICE NOT CONFIGURED:
      Oban's `cron:` service is missing or disabled, so it carries no crontab.
      The critical maintenance workers will not run, which leads to job
      accumulation and queue problems going unreported. Add
      `cron: [crontab: [...]]` to the Oban config with the required jobs.
      """,
      critical_workers: LogFormat.reason(@critical_workers)
    )
  end

  defp warn(missing_workers) do
    Enum.each(missing_workers, fn worker ->
      Logger.warning(
        "Critical Oban worker not scheduled in the cron service: #{inspect(worker)}. " <>
          "This worker should run periodically for system health."
      )
    end)
  end

  defp crontab({_module, opts}) when is_list(opts), do: Keyword.get(opts, :crontab)
  defp crontab(opts) when is_list(opts), do: Keyword.get(opts, :crontab)

  # Absent, `false`, or an alternative implementation named as a bare module:
  # no crontab of ours to read.
  defp crontab(_other), do: nil

  defp scheduled?(crontab, worker) do
    Enum.any?(crontab, fn
      {_schedule, ^worker} -> true
      {_schedule, ^worker, _opts} -> true
      _other -> false
    end)
  end
end
