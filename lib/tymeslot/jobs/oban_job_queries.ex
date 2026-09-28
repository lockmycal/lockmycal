defmodule Tymeslot.Jobs.ObanJobQueries do
  @moduledoc """
  Query interface for Oban job-related database operations.
  """
  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias Oban.Job
  alias Oban.Worker
  alias Tymeslot.Repo

  @doc """
  Returns the args currently stored on a job's row, or `nil` when no row exists.

  A worker whose uniqueness covers `:executing` with `replace: [:args]` can have
  its row's args rewritten by a conflicting insert while it runs; the running
  process only ever sees the args it started with. Rereading the row is how such
  a worker notices the replacement before it finishes.
  """
  @spec get_current_args(Job.t()) :: map() | nil
  def get_current_args(%Job{id: id}) when is_integer(id) do
    Repo.one(from(j in Job, where: j.id == ^id, select: j.args))
  end

  def get_current_args(%Job{}), do: nil

  @doc """
  Counts maintenance worker jobs in active states.

  `suspended` is treated as active: a suspended job has not reached a terminal
  state and may resume, so it must count as pending to keep this manual
  duplicate-prevention check in agreement with Oban's `unique: [states: ...]`
  guards on the workers.
  """
  @spec count_active_maintenance_jobs(module() | String.t()) :: non_neg_integer()
  def count_active_maintenance_jobs(worker) do
    worker_name = normalize_worker_name(worker)

    query =
      from(j in Job,
        where: j.worker == ^worker_name,
        where: j.state in ["available", "scheduled", "executing", "suspended"],
        select: count(j.id)
      )

    Repo.one(query)
  end

  @doc """
  Returns distinct `user_id` values from `args` for jobs of the given worker
  whose `args["action"]` is in `actions` and whose state is not yet terminal
  (`available`, `scheduled`, `executing`, `retryable`, or `suspended`).

  `suspended` jobs are included so this check agrees with the workers' Oban
  `unique: [states: ...]` guards — a suspended job is still pending and must
  not allow a duplicate to be enqueued.

  Useful for workers that must avoid enqueueing additional actions for a user
  while any related action is still pending.
  """
  @spec user_ids_with_pending_jobs_for_actions(module() | String.t(), [String.t()]) :: [
          integer()
        ]
  def user_ids_with_pending_jobs_for_actions(worker, actions) do
    worker_name = normalize_worker_name(worker)

    Repo.all(
      from(j in Job,
        where: j.worker == ^worker_name,
        where: j.state in ["available", "scheduled", "executing", "retryable", "suspended"],
        where: fragment("?->>'action' = ANY(?)", j.args, ^actions),
        distinct: true,
        select: fragment("(?->>'user_id')::bigint", j.args)
      )
    )
  end

  @doc """
  Gets all stuck executing jobs older than the given threshold.
  """
  @spec get_stuck_executing_jobs(DateTime.t()) :: [Job.t()]
  def get_stuck_executing_jobs(threshold_datetime) do
    query =
      from(j in Job,
        where: j.state == "executing",
        where: j.attempted_at < ^threshold_datetime,
        select: j
      )

    Repo.all(query)
  end

  @doc """
  Updates a job to discarded state with error information.
  """
  @spec update_job_to_discarded(Job.t(), map()) ::
          {:ok, Job.t()} | {:error, Ecto.Changeset.t()}
  def update_job_to_discarded(job, error_info) do
    existing_errors = job.errors || []

    job
    |> Changeset.change(%{
      state: "discarded",
      discarded_at: DateTime.utc_now(),
      errors: existing_errors ++ [error_info]
    })
    |> Repo.update()
  end

  # The state list every "still pending" delete below matches against. Kept
  # in one place because it has to stay in step with the `unique: [states:
  # ...]` guard on whichever worker is being cleared.
  @pending_states ~w(available scheduled retryable)

  @doc """
  Deletes any pending job for one meeting and one action.

  Generalises the reminder deletion below for the approval jobs, which key on
  the meeting alone. Worker names are normalised through `normalize_worker_name/1`
  for the same reason: Oban stores them without the `Elixir.` prefix, so a raw
  module name would silently match nothing and leave the job to fire.
  """
  @spec delete_jobs_by_action(module(), String.t(), term()) :: {non_neg_integer(), nil}
  def delete_jobs_by_action(worker_module, action, meeting_id) do
    args_match = %{"action" => action, "meeting_id" => meeting_id}
    delete_pending_jobs(worker_module, args_match, queue: "emails")
  end

  @doc """
  Deletes every pending job a worker holds for one meeting, on any queue.

  `delete_jobs_by_action/3` above is scoped to the `emails` queue, which is
  correct for the email jobs it was written for but silently matches nothing
  for a worker that runs anywhere else. The approval expiry job is one of
  those, and a missed deletion there is not cosmetic: it fires after the host
  has already answered and tries to expire a request that is no longer open.
  """
  @spec delete_meeting_jobs(module(), term()) :: {non_neg_integer(), nil}
  def delete_meeting_jobs(worker_module, meeting_id) do
    args_match = %{"meeting_id" => meeting_id}
    delete_pending_jobs(worker_module, args_match)
  end

  @doc """
  Deletes existing reminder email jobs for a meeting to avoid duplicates
  when rescheduling.
  """
  @spec delete_reminder_jobs_for_meeting(term(), module(), map()) ::
          {non_neg_integer(), nil}
  def delete_reminder_jobs_for_meeting(meeting_id, worker_module, reminder_params) do
    args_match =
      Map.merge(
        %{"action" => "send_reminder_emails", "meeting_id" => meeting_id},
        reminder_params
      )

    delete_pending_jobs(worker_module, args_match, queue: "emails")
  end

  @doc """
  Deletes pending poll email jobs (deadline reminders and host nudges) for a poll.

  Used when a poll is confirmed or cancelled, so no reminder or nudge fires for a
  poll that is no longer collecting votes. Matches on the `poll_id` embedded in
  the job args regardless of action or variant.
  """
  @spec delete_poll_jobs(term(), module()) :: {non_neg_integer(), nil}
  def delete_poll_jobs(poll_id, worker_module) do
    args_match = %{"poll_id" => poll_id}
    delete_pending_jobs(worker_module, args_match, queue: "emails")
  end

  # Workers whose bare `integration_id` arg names a calendar integration, and
  # those whose names a video one. The two tables share an integer id space, so
  # the key alone can't say whose row a job points at; the worker (and, for the
  # health worker, its `type` arg) can.
  @calendar_integration_workers ["Tymeslot.Integrations.Calendar.TokenRefreshJob"]
  @video_integration_workers ["Tymeslot.Workers.VideoIntegrationDisconnectWorker"]
  @health_worker "Tymeslot.Workers.IntegrationHealthWorker"

  @doc """
  Whether any job tied to one of the user's meetings or booking payments is
  still due to run: available, executing, retryable, or scheduled to fire
  within `due_within_seconds`.

  Backs the account-deletion purge, which must not delete the rows those jobs
  read (a cancellation email reloads its meeting, a refund email its payment)
  until they have run. A job scheduled far ahead is not waited for — the
  meetings it belongs to were just cancelled, so it is a leftover the purge
  removes rather than a delivery still owed.
  """
  @spec pending_meeting_jobs_for_user?(pos_integer(), DateTime.t(), pos_integer()) :: boolean()
  def pending_meeting_jobs_for_user?(user_id, %DateTime{} = now, due_within_seconds) do
    due_before = DateTime.add(now, due_within_seconds, :second)

    Job
    |> where(
      [j],
      j.state in ["available", "executing", "retryable"] or
        (j.state == "scheduled" and j.scheduled_at <= ^due_before)
    )
    |> where(
      [j],
      fragment("?->>'meeting_id'", j.args) in subquery(user_meeting_ids(user_id)) or
        fragment("?->>'booking_payment_id'", j.args) in subquery(user_payment_ids(user_id))
    )
    |> Repo.exists?()
  end

  @doc """
  Deletes every not-yet-running job that belongs to the user: keyed by their
  `user_id`, or by the id of a row they own (meeting, booking payment, poll,
  webhook, calendar-grid video room, calendar or video integration).

  Runs inside the account-deletion transaction, right before the user row is
  deleted, so a rollback puts the jobs back. Deleted rather than cancelled so
  the personal data in their args goes with them instead of lingering until
  the Oban pruner. `executing` jobs are left alone — they are already running.
  Jobs of `except_worker` (the deletion worker itself) are never touched.
  """
  @spec delete_pending_jobs_for_user(pos_integer(), module()) :: {non_neg_integer(), nil}
  def delete_pending_jobs_for_user(user_id, except_worker) do
    except_name = normalize_worker_name(except_worker)

    Job
    |> where([j], j.state in ^(@pending_states ++ ["suspended"]))
    |> where([j], j.worker != ^except_name)
    |> where(^owned_by_user(user_id))
    |> Repo.delete_all()
  end

  defp owned_by_user(user_id) do
    calendar_ids = user_owned_ids("calendar_integrations", user_id)
    video_ids = user_owned_ids("video_integrations", user_id)

    keyed_by_owned_row =
      Enum.reduce(
        [
          {"meeting_id", user_meeting_ids(user_id)},
          {"booking_payment_id", user_payment_ids(user_id)},
          {"poll_id", user_owned_ids("polls", user_id)},
          {"webhook_id", user_owned_ids("webhooks", user_id)},
          {"event_room_id", user_owned_ids("calendar_event_video_rooms", user_id)},
          {"calendar_integration_id", calendar_ids}
        ],
        dynamic([j], fragment("?->>'user_id'", j.args) == ^to_string(user_id)),
        fn {key, ids}, acc ->
          dynamic([j], ^acc or fragment("?->>?", j.args, ^key) in subquery(ids))
        end
      )

    dynamic([j], ^keyed_by_owned_row or ^keyed_by_integration(calendar_ids, video_ids))
  end

  defp keyed_by_integration(calendar_ids, video_ids) do
    integration_id = dynamic([j], fragment("?->>'integration_id'", j.args))
    health_type = dynamic([j], fragment("?->>'type'", j.args))

    calendar_job =
      dynamic(
        [j],
        j.worker in @calendar_integration_workers or
          (j.worker == @health_worker and ^health_type == "calendar")
      )

    video_job =
      dynamic(
        [j],
        j.worker in @video_integration_workers or
          (j.worker == @health_worker and ^health_type == "video")
      )

    dynamic(
      [j],
      (^calendar_job and ^integration_id in subquery(calendar_ids)) or
        (^video_job and ^integration_id in subquery(video_ids))
    )
  end

  defp user_meeting_ids(user_id) do
    from(m in "meetings",
      where: m.organizer_user_id == ^user_id,
      select: fragment("?::text", m.id)
    )
  end

  defp user_payment_ids(user_id) do
    from(p in "booking_payments",
      where: p.host_user_id == ^user_id,
      select: fragment("?::text", p.id)
    )
  end

  defp user_owned_ids(table, user_id) do
    from(r in table, where: r.user_id == ^user_id, select: fragment("?::text", r.id))
  end

  defp delete_pending_jobs(worker_module, args_match, opts \\ []) do
    worker_name = normalize_worker_name(worker_module)
    queue = Keyword.get(opts, :queue)

    Job
    |> where([j], j.worker == ^worker_name)
    |> where([j], j.state in @pending_states)
    |> where([j], fragment("? @> ?::jsonb", j.args, type(^args_match, :map)))
    |> queue_filter(queue)
    |> Repo.delete_all()
  end

  defp queue_filter(query, nil), do: query
  defp queue_filter(query, queue), do: where(query, [j], j.queue == ^queue)

  @doc """
  Lists queues with accumulated available jobs exceeding the threshold.
  Returns a list of `{queue_name, count}` tuples.
  """
  @spec list_accumulated_jobs(DateTime.t()) :: [{String.t(), non_neg_integer()}]
  def list_accumulated_jobs(recent_cutoff) do
    Repo.all(
      from(j in Job,
        where: j.state == "available",
        where: j.inserted_at > ^recent_cutoff,
        group_by: j.queue,
        select: {j.queue, count(j.id)}
      )
    )
  end

  @doc """
  Lists queues with available jobs older than the cutoff time.
  Returns a list of `{queue_name, count}` tuples.
  """
  @spec list_stuck_available_jobs(DateTime.t(), DateTime.t()) ::
          [{String.t(), non_neg_integer()}]
  def list_stuck_available_jobs(cutoff_time, recent_cutoff) do
    Repo.all(
      from(j in Job,
        where: j.state == "available",
        where: j.inserted_at < ^cutoff_time,
        where: j.inserted_at > ^recent_cutoff,
        group_by: j.queue,
        select: {j.queue, count(j.id)}
      )
    )
  end

  @doc """
  Lists queues with retryable jobs past their scheduled retry time.
  Returns a list of `{queue_name, count}` tuples.
  """
  @spec list_stuck_retryable_jobs(DateTime.t(), DateTime.t(), DateTime.t()) ::
          [{String.t(), non_neg_integer()}]
  def list_stuck_retryable_jobs(now, cutoff_time, recent_cutoff) do
    Repo.all(
      from(j in Job,
        where: j.state == "retryable",
        where: j.scheduled_at < ^now,
        where: j.scheduled_at < ^cutoff_time,
        where: j.inserted_at > ^recent_cutoff,
        group_by: j.queue,
        select: {j.queue, count(j.id)}
      )
    )
  end

  @doc """
  Whether another job of `worker` for `meeting_id` started executing before
  `job` did and is executing still.

  "Before" is the order the jobs were fetched in, `attempted_at` with the id as
  a tie-break, not the order they were enqueued in. Enqueue order is not start
  order: priorities differ by action, a retry runs again under its old id, and
  a job snoozed behind a third one can wake after a newer job has begun. The
  order is strict, so of any two executing jobs exactly one sees the other,
  and the queue cannot wedge with both sides waiting.

  Oban's `unique` cannot express this: it decides whether a job is inserted at
  all, whereas this is about when an inserted job may run.
  """
  @spec earlier_job_executing?(module() | String.t(), term(), Job.t()) :: boolean()
  def earlier_job_executing?(worker, meeting_id, %Job{id: id, attempted_at: %DateTime{} = started})
      when is_integer(id) do
    worker_name = normalize_worker_name(worker)

    Repo.exists?(
      from(j in Job,
        where: j.id != ^id,
        where: j.state == "executing",
        where: j.worker == ^worker_name,
        where: fragment("?->>'meeting_id' = ?", j.args, ^to_string(meeting_id)),
        where: j.attempted_at < ^started or (j.attempted_at == ^started and j.id < ^id)
      )
    )
  end

  # Oban stores worker names without the "Elixir." prefix; `Worker.to_string/1`
  # normalises a module into that form so a match against `j.worker` can't
  # silently miss every job. Callers that already hold the stored name (e.g. a
  # worker's own `to_string(__MODULE__)`-shaped literal) pass it straight through.
  defp normalize_worker_name(worker) when is_atom(worker), do: Worker.to_string(worker)
  defp normalize_worker_name(worker) when is_binary(worker), do: worker
end
