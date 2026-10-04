defmodule Tymeslot.Workers.BookerCalendarEventWorker do
  @moduledoc """
  Keeps a signed-in booker's own calendar copy of a meeting in step with the
  meeting (`Tymeslot.Meetings.BookerCalendarSync`).

  Enqueued by `Tymeslot.Meetings.BookerCalendar.follow/1` for every write to
  the organiser's calendar. Each job reads the meeting afresh and converges on
  it, so one queued job stands for any number of changes that have not been
  synced yet, and only one job per meeting runs at a time.
  """

  use Oban.Worker,
    queue: :calendar_events,
    max_attempts: 5,
    priority: 2

  alias Tymeslot.Infrastructure.ExpectedJobOutcome
  alias Tymeslot.Jobs.ObanJobQueries
  alias Tymeslot.Meetings.BookerCalendarSync
  alias Tymeslot.Workers.SnoozePolicy

  @behaviour ExpectedJobOutcome

  @calendar_timeout_ms 90_000
  @write_wait_seconds 2
  @write_wait_jitter_seconds 1
  @max_write_waits 8

  # The booker's calendar refused the credentials: only reconnecting it helps,
  # and the copy is optional, so nobody is alerted.
  @unauthorized "Booker's calendar refused authentication"

  @impl ExpectedJobOutcome
  def expected_outcome?(reason), do: reason == @unauthorized

  @doc """
  A sync job for `meeting_id`. A job not yet running already covers whatever
  changed since it was enqueued, so another is not added beside it; one that
  is running has read the meeting, so a new one is.
  """
  @spec new_sync(String.t()) :: Oban.Job.changeset()
  def new_sync(meeting_id) do
    new(%{"meeting_id" => meeting_id},
      unique: [
        period: 300,
        fields: [:args, :worker],
        keys: [:meeting_id],
        states: [:available, :scheduled, :retryable]
      ]
    )
  end

  @impl Oban.Worker
  def timeout(_job), do: @calendar_timeout_ms

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"meeting_id" => meeting_id}} = job) do
    case wait_behind_earlier_sync(job, meeting_id) do
      {:snooze, seconds} -> {:snooze, seconds}
      :go -> meeting_id |> BookerCalendarSync.sync() |> handle_result()
    end
  end

  defp wait_behind_earlier_sync(%Oban.Job{id: id, attempted_at: %DateTime{}} = job, meeting_id)
       when is_integer(id) do
    if ObanJobQueries.earlier_job_executing?(__MODULE__, meeting_id, job) do
      case SnoozePolicy.snooze_or_exhaust(SnoozePolicy.executions(job),
             max_snoozes: @max_write_waits,
             base_seconds: @write_wait_seconds,
             jitter_seconds: @write_wait_jitter_seconds
           ) do
        {:snooze, seconds} -> {:snooze, seconds}
        :exhausted -> :go
      end
    else
      :go
    end
  end

  # `Oban.Testing.perform_job/3` builds a job that was never inserted.
  defp wait_behind_earlier_sync(_job, _meeting_id), do: :go

  defp handle_result(:ok), do: :ok
  defp handle_result({:error, :unauthorized}), do: {:discard, @unauthorized}
  defp handle_result({:error, :rate_limited}), do: {:snooze, 60}
  defp handle_result({:error, :circuit_open}), do: {:snooze, 120}
  defp handle_result({:error, reason}), do: {:error, reason}
end
