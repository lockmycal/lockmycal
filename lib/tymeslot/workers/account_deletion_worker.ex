defmodule Tymeslot.Workers.AccountDeletionWorker do
  @moduledoc """
  Runs a requested account deletion in the background, in two steps (see
  `Tymeslot.Auth.AccountDeletion` for why it is split):

    * `"prepare"` — `AccountDeletion.prepare/1`: external clean-up hook,
      cancelling upcoming meetings, expiring checkouts, revoking OAuth access.
      Then enqueues the `"purge"` step. A hook failure returns an error so
      Oban retries it.
    * `"purge"` — waits (snoozing) while jobs the cancellations queued are
      still due to run, or while a video integration's rooms are still being
      deleted at the provider (`VideoIntegrationDisconnectWorker`), then `AccountDeletion.purge/2`. The wait is capped at
      `@purge_wait_cap_seconds` after the purge was first enqueued: a job
      stuck retrying must not keep a deleted-on-request account alive
      forever, so after the cap the purge goes ahead and deletes what is left.

  Both steps are no-ops for a user who no longer exists.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 10,
    unique: [
      period: :infinity,
      fields: [:args, :worker],
      keys: [:user_id, :step],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias Tymeslot.Auth.{AccountDeletion, UserQueries}
  alias Tymeslot.Jobs.ObanJobQueries

  @purge_delay_seconds 60
  @purge_snooze_seconds 60
  @purge_wait_cap_seconds 24 * 60 * 60
  # A job due later than this is a leftover of a cancelled meeting (a reminder
  # the cancel flow somehow missed), not a delivery still owed.
  @due_within_seconds 15 * 60

  @doc "Builds the first (`\"prepare\"`) job for a requested deletion."
  @spec new_prepare(pos_integer(), AccountDeletion.actor()) :: Oban.Job.changeset()
  def new_prepare(user_id, actor) do
    new(Map.merge(%{"user_id" => user_id, "step" => "prepare"}, encode_actor(actor)))
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "step" => step} = args} = job) do
    case UserQueries.get_user(user_id) do
      {:error, :not_found} -> :ok
      {:ok, user} -> run(step, user, args, job)
    end
  end

  defp run("prepare", user, args, _job) do
    with {:ok, summary} <- AccountDeletion.prepare(user),
         {:ok, _job} <- enqueue_purge(args, summary) do
      :ok
    end
  end

  defp run("purge", user, args, job) do
    now = DateTime.utc_now()

    if work_pending?(user.id, now) and
         DateTime.diff(now, job.inserted_at) < @purge_wait_cap_seconds do
      {:snooze, @purge_snooze_seconds}
    else
      context = %{
        actor: decode_actor(args),
        meetings_cancelled: args["meetings_cancelled"],
        meetings_failed: args["meetings_failed"],
        manual_refunds: args["manual_refunds"]
      }

      case AccountDeletion.purge(user, context) do
        {:ok, _deleted} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp work_pending?(user_id, now) do
    ObanJobQueries.pending_meeting_jobs_for_user?(user_id, now, @due_within_seconds) or
      AccountDeletion.video_cleanup_pending?(user_id)
  end

  defp enqueue_purge(args, summary) do
    args
    |> Map.merge(%{
      "step" => "purge",
      "meetings_cancelled" => summary.meetings_cancelled,
      "meetings_failed" => summary.meetings_failed,
      "manual_refunds" => summary.manual_refunds
    })
    |> new(schedule_in: @purge_delay_seconds)
    |> Oban.insert()
  end

  defp encode_actor(:self), do: %{"actor" => "self"}
  defp encode_actor({:admin, admin_id}), do: %{"actor" => "admin", "actor_user_id" => admin_id}
  defp encode_actor(:system), do: %{"actor" => "system"}

  defp decode_actor(%{"actor" => "self"}), do: :self
  defp decode_actor(%{"actor" => "admin", "actor_user_id" => id}), do: {:admin, id}
  defp decode_actor(_args), do: :system
end
