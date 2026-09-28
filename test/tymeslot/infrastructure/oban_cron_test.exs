defmodule Tymeslot.Infrastructure.ObanCronTest do
  # `capture_log/1` sees the whole log stream for the duration of its block, so
  # the "stays quiet" assertions here would trip over a concurrently running
  # test's output. Absence assertions on logs mean this module runs alone.
  use ExUnit.Case, async: false

  @moduletag :infrastructure
  @moduletag :unit

  import ExUnit.CaptureLog

  alias Config.Reader
  alias Tymeslot.Infrastructure.ObanCron
  alias Tymeslot.Workers.ObanMaintenanceWorker
  alias Tymeslot.Workers.ObanQueueMonitorWorker

  defp cron_config(crontab), do: [repo: Tymeslot.Repo, cron: [crontab: crontab]]

  defp both_workers do
    [
      {"*/30 * * * *", ObanMaintenanceWorker},
      {"0 * * * *", ObanQueueMonitorWorker}
    ]
  end

  describe "missing_workers/1" do
    test "finds nothing missing when the crontab schedules both critical workers" do
      assert ObanCron.missing_workers(cron_config(both_workers())) == []
    end

    test "reads a crontab entry that carries its own options" do
      crontab = [
        {"*/30 * * * *", ObanMaintenanceWorker, args: %{}},
        {"0 * * * *", ObanQueueMonitorWorker, args: %{}}
      ]

      assert ObanCron.missing_workers(cron_config(crontab)) == []
    end

    test "names the worker the crontab leaves out" do
      crontab = [{"*/30 * * * *", ObanMaintenanceWorker}]

      assert ObanCron.missing_workers(cron_config(crontab)) == [ObanQueueMonitorWorker]
    end

    test "reads the {module, opts} form of the cron service" do
      config = [cron: {Oban.Cron, crontab: both_workers()}]

      assert ObanCron.missing_workers(config) == []
    end

    test "reports no crontab when the cron service is absent or switched off" do
      assert ObanCron.missing_workers(repo: Tymeslot.Repo) == :no_crontab
      assert ObanCron.missing_workers(cron: false) == :no_crontab
      assert ObanCron.missing_workers(cron: Oban.Cron) == :no_crontab
    end

    # This check reads the raw application environment, so it is coupled to the
    # shape the config is written in. Oban 2.24 hoisted the crontab out of
    # `plugins:` and into `cron:`; a config left on the old shape reports as
    # having no crontab at all, which is precisely the silent failure this
    # pairing has to be tested for rather than assumed.
    test "does not find a crontab left behind in the pre-2.24 plugins list" do
      config = [plugins: [{Oban.Plugins.Cron, crontab: both_workers()}]]

      assert ObanCron.missing_workers(config) == :no_crontab
    end
  end

  # This module reads the raw application environment, so it is only ever as
  # good as its agreement with the config files: the config file is where a
  # rename lands, and this module is where that rename gets missed. Reading the
  # real config back and validating it is what stops the two drifting apart in
  # silence. `runtime.exs` cannot be read this way (it wants the production
  # environment), but all three config files carry the same shape.
  #
  # The crontab itself lives under the separate `:oban_cron` key (not nested
  # inside `config :tymeslot, Oban` — see `build/1`'s moduledoc), so it has to
  # be merged in the same way `oban_config/0` does before `missing_workers/1`
  # can read it back.
  describe "the project's own configuration" do
    test "schedules every critical worker in a shape this module can read" do
      dev_config =
        [__DIR__, "..", "..", "..", "config", "dev.exs"]
        |> Path.join()
        |> Path.expand()
        |> Reader.read!(env: :dev, target: :host)

      oban_cron = get_in(dev_config, [:tymeslot, :oban_cron]) || []

      config =
        dev_config
        |> get_in([:tymeslot, Oban])
        |> Keyword.put(:cron, crontab: oban_cron)

      assert ObanCron.missing_workers(config) == []
    end
  end

  describe "merge/2" do
    test "concatenates base and additional entries" do
      base = [{"0 * * * *", ObanQueueMonitorWorker}]
      additional = [{"*/30 * * * *", ObanMaintenanceWorker}]

      assert ObanCron.merge(base, additional) == base ++ additional
    end

    test "rejects an entry that isn't a valid {cron_string, worker} tuple" do
      assert_raise ArgumentError, ~r/:oban_cron must be a list of/, fn ->
        ObanCron.merge([{123, ObanMaintenanceWorker}], [])
      end

      assert_raise ArgumentError, ~r/:oban_additional_cron must be a list of/, fn ->
        ObanCron.merge([], [{"0 * * * *", "NotAModule"}])
      end
    end
  end

  describe "build/1" do
    test "merges the project's configured :oban_cron and :oban_additional_cron" do
      config = ObanCron.build(repo: Tymeslot.Repo)

      assert Keyword.get(config, :cron) ==
               [crontab: Application.get_env(:tymeslot, :oban_cron, [])]
    end
  end

  describe "warn_on_missing_workers/1" do
    test "stays quiet when both critical workers are scheduled" do
      log =
        capture_log(fn ->
          assert :ok = ObanCron.warn_on_missing_workers(cron_config(both_workers()))
        end)

      refute log =~ "Critical Oban worker"
      refute log =~ "OBAN CRON SERVICE NOT CONFIGURED"
    end

    test "names each unscheduled worker" do
      crontab = [{"0 * * * *", ObanQueueMonitorWorker}]

      log = capture_log(fn -> ObanCron.warn_on_missing_workers(cron_config(crontab)) end)

      assert log =~ "Critical Oban worker not scheduled"
      assert log =~ "ObanMaintenanceWorker"
      refute log =~ "ObanQueueMonitorWorker."
    end

    test "warns once about the service itself when there is no crontab" do
      log = capture_log(fn -> ObanCron.warn_on_missing_workers(repo: Tymeslot.Repo) end)

      assert log =~ "OBAN CRON SERVICE NOT CONFIGURED"
      assert log =~ "critical maintenance workers will not run"
    end
  end
end
