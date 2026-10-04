defmodule Tymeslot.Auth.AccountDeletion do
  @moduledoc """
  Orchestrates account deletion.

  Deletion is a hard delete of the user and everything they own, including
  their meeting history, and runs in two parts:

    1. `request/2` — synchronous and fast. Checks the last-admin guard, marks
       the account (`deletion_requested_at`, plus `disabled_at` so it can no
       longer log in or be booked), enqueues
       `Tymeslot.Workers.AccountDeletionWorker`, and revokes every session.
    2. The worker, in the background:
       * `prepare/1` — runs the external-cleanup hook (e.g. SaaS subscription
         cancellation), cancels the user's upcoming meetings through the
         ordinary cancel flow so every invitee is told and refunded, expires
         open checkouts, deletes the provider-side video rooms that outlive
         their meeting (see `delete_lingering_video_rooms/1`), and revokes
         OAuth access at the providers.
       * `purge/2` — once the notifications that cancelling queued and the
         video-room clean-up have finished, runs the anonymise-then-delete transaction and removes the files
         the deleted rows pointed at.

  The split exists because cancelling queues jobs (cancellation and refund
  emails, calendar and video clean-up) that reload the meeting or payment when
  they run. Deleting the user in the same breath would cascade those rows away
  first and every one of those jobs would find nothing to send.

  `delete_account/1` is the old one-shot path (hook, then purge) without the
  meeting cancellation, kept for callers that delete an account directly.
  """

  require Logger

  alias Tymeslot.Auth.{AdminUserQueries, Session, UserQueries, UserSchema, UserSessionQueries}
  alias Tymeslot.Auth.Helpers.AccountLogging
  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Integrations.AccessRevocation
  alias Tymeslot.Integrations.Video
  alias Tymeslot.Integrations.Video.ProviderConfig, as: VideoProviderConfig
  alias Tymeslot.Integrations.Video.VideoIntegrationQueries
  alias Tymeslot.Jobs.ObanJobQueries
  alias Tymeslot.MeetingPayments
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.{MeetingListQueries, MeetingState}
  alias Tymeslot.Profiles
  alias Tymeslot.Repo
  alias Tymeslot.Security.{Password, SecurityLogger}
  alias Tymeslot.ThemeCustomizations
  alias Tymeslot.Workers.AccountDeletionWorker

  @typedoc "Who asked for the deletion: the user, an admin (by id), or the system."
  @type actor :: :self | {:admin, pos_integer()} | :system

  @type prepare_summary :: %{
          meetings_cancelled: non_neg_integer(),
          meetings_failed: non_neg_integer(),
          manual_refunds: [String.t()]
        }

  @doc """
  Schedules the user's account for deletion.

  Refuses to delete the install's last remaining admin (`{:error, :last_admin}`),
  counting only admins not already scheduled for deletion, under the same
  admin-row lock `Tymeslot.Auth.AccountStatus` takes. Idempotent: a user whose
  deletion is already scheduled is returned unchanged.

  Sessions are revoked only after the transaction commits: disconnecting live
  sockets for a request that then rolled back would be wrong.
  """
  @spec request(UserSchema.t(), actor()) ::
          {:ok, UserSchema.t()} | {:error, :last_admin | :not_found | term()}
  def request(%UserSchema{id: user_id}, actor) do
    result =
      Repo.transaction(fn ->
        AdminUserQueries.lock_admins()

        case UserQueries.get_user(user_id) do
          {:error, :not_found} -> Repo.rollback(:not_found)
          {:ok, %UserSchema{deletion_requested_at: %DateTime{}} = user} -> {:existing, user}
          {:ok, user} -> {:new, mark_and_enqueue(user, actor)}
        end
      end)

    case result do
      {:ok, {:new, user}} ->
        Session.revoke_all_sessions(user.id)
        log_success("account_deletion_request", user.id, actor, %{})
        {:ok, user}

      {:ok, {:existing, user}} ->
        {:ok, user}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  Whether the user confirms a deletion with their password. An account with
  no password (signed up through OAuth) confirms by typing its email instead.
  """
  @spec confirms_with_password?(UserSchema.t()) :: boolean()
  def confirms_with_password?(%UserSchema{password_hash: hash}), do: is_binary(hash)

  @doc """
  Checks the confirmation a user gave for deleting their own account:
  `params["current_password"]` for an account with a password, otherwise
  `params["email_confirmation"]` matching the account email (trimmed,
  case-insensitive).
  """
  @spec verify_confirmation(UserSchema.t(), map()) ::
          :ok | {:error, :invalid_password | :email_mismatch}
  def verify_confirmation(%UserSchema{password_hash: hash}, params) when is_binary(hash) do
    case params["current_password"] do
      password when is_binary(password) and password != "" ->
        if Password.verify_password(password, hash), do: :ok, else: {:error, :invalid_password}

      _missing ->
        # Still pay for a hash check, so an empty submission takes as long as
        # a wrong one.
        Password.no_user_verify()
        {:error, :invalid_password}
    end
  end

  def verify_confirmation(%UserSchema{email: email}, params) do
    typed = params["email_confirmation"]

    if is_binary(typed) and normalize_email(typed) == normalize_email(email) do
      :ok
    else
      {:error, :email_mismatch}
    end
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp mark_and_enqueue(user, actor) do
    with :ok <- check_last_admin(user),
         {:ok, marked} <- UserQueries.mark_deletion_requested(user, DateTime.utc_now(:second)),
         {:ok, _job} <- Oban.insert(AccountDeletionWorker.new_prepare(marked.id, actor)) do
      marked
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp check_last_admin(user) do
    if last_admin?(user), do: {:error, :last_admin}, else: :ok
  end

  @doc """
  Whether `user` is an admin and the only one not already scheduled for
  deletion — deleting them would leave the install without an admin.
  """
  @spec last_admin?(UserSchema.t()) :: boolean()
  def last_admin?(%UserSchema{is_admin: true}),
    do: AdminUserQueries.count_admins_not_pending_deletion() <= 1

  def last_admin?(%UserSchema{}), do: false

  @doc """
  Everything that has to happen while the user's rows still exist: the
  external-cleanup hook, cancelling upcoming meetings, expiring open
  checkouts, deleting lingering video rooms, and revoking OAuth access at the
  providers.

  Only a hook failure is returned as an error (the worker retries): we never
  go on to destroy a user while external state that keeps costing them money
  could not be cancelled. Everything after the hook is best effort — a meeting
  that fails to cancel, or a refund that fails (logged as needing a manual
  refund), does not stop the deletion.
  """
  @spec prepare(UserSchema.t()) :: {:ok, prepare_summary()} | {:error, term()}
  def prepare(%UserSchema{id: user_id} = user) do
    with :ok <- run_account_deletion_hook(user_id) do
      summary = cancel_upcoming_meetings(user_id)
      expire_open_checkouts(user)
      delete_lingering_video_rooms(user_id)
      AccessRevocation.revoke_for_user(user_id)
      {:ok, summary}
    end
  end

  # A provider whose rooms stay on the organiser's server until something
  # deletes them (`VideoProviderConfig.rooms_deleted_after_meeting/0`) would
  # keep every room — grid events and ended meetings included — once the
  # credentials are gone. Disconnecting with the rooms drains them in the
  # background; `AccountDeletionWorker` waits for that before purging. Rooms of
  # integrations the user had already disconnected are drained by their own job.
  defp delete_lingering_video_rooms(user_id) do
    lingering = VideoProviderConfig.rooms_deleted_after_meeting()

    user_id
    |> VideoIntegrationQueries.list_all_for_user()
    |> Enum.filter(&(&1.provider in lingering))
    |> Enum.each(fn integration ->
      case Video.delete_integration(user_id, integration.id, delete_rooms: true) do
        {:error, reason} ->
          Logger.warning("Could not schedule video room clean-up for account deletion",
            user_id: user_id,
            integration_id: integration.id,
            reason: LogFormat.reason(reason)
          )

        {:ok, _outcome} ->
          :ok
      end
    end)
  end

  @doc """
  Whether the user is still waiting on provider-side video-room clean-up that
  a purge would cut short.
  """
  @spec video_cleanup_pending?(pos_integer()) :: boolean()
  def video_cleanup_pending?(user_id), do: VideoIntegrationQueries.deleted_for_user?(user_id)

  defp cancel_upcoming_meetings(user_id) do
    user_id
    |> MeetingListQueries.list_upcoming_active_for_organizer(DateTime.utc_now())
    |> Enum.reduce(%{meetings_cancelled: 0, meetings_failed: 0, manual_refunds: []}, fn
      meeting, acc -> tally(acc, cancel_meeting(meeting, user_id))
    end)
  end

  defp tally(acc, :cancelled), do: Map.update!(acc, :meetings_cancelled, &(&1 + 1))
  defp tally(acc, :failed), do: Map.update!(acc, :meetings_failed, &(&1 + 1))

  defp tally(acc, {:manual_refund, payment_id}) do
    acc
    |> Map.update!(:meetings_cancelled, &(&1 + 1))
    |> Map.update!(:manual_refunds, &[payment_id | &1])
  end

  defp cancel_meeting(meeting, user_id) do
    {refund_action, payment} = refund_for(meeting, user_id)

    case Meetings.cancel_meeting_with_refund(meeting, user_id, refund_action) do
      {:ok, _cancelled} ->
        :cancelled

      {:error, {:refund_failed, reason}} ->
        Logger.error(
          "Meeting cancelled for account deletion but refund failed; manual refund required",
          user_id: user_id,
          meeting_id: meeting.id,
          booking_payment_id: payment.id,
          reason: LogFormat.reason(reason)
        )

        {:manual_refund, payment.id}

      {:error, reason} ->
        Logger.warning("Could not cancel meeting during account deletion",
          user_id: user_id,
          meeting_id: meeting.id,
          reason: LogFormat.reason(reason)
        )

        :failed
    end
  end

  # A held request refunds itself when it is withdrawn (`Approval.withdraw/2`),
  # so it is cancelled without a refund action of its own; asking for one on
  # top would refund the attendee twice. Anything else gets back whatever is
  # left of what they paid.
  defp refund_for(meeting, user_id) do
    payment = MeetingPayments.payment_for_meeting(meeting.id, user_id)

    if MeetingState.awaiting_approval?(meeting) do
      {:none, payment}
    else
      {:ok, refund_action} = Meetings.resolve_cancellation_refund(payment, %{})
      {refund_action, payment}
    end
  end

  # Meetings still waiting for their checkout to be paid are not cancelled
  # above: their Stripe session is expired here so the invitee can no longer
  # pay for a booking that is about to disappear.
  defp expire_open_checkouts(user) do
    case MeetingPayments.disconnect(%{id: user.id}) do
      {:ok, _summary} ->
        :ok

      {:error, reason} ->
        Logger.warning("Could not expire open checkouts during account deletion",
          user_id: user.id,
          reason: LogFormat.reason(reason)
        )
    end
  end

  @doc """
  Deletes the user and everything they own.

  Runs `Tymeslot.MeetingPayments.anonymise_host/1` before the delete so
  booking-payment and payment-transaction rows are scrubbed and marked
  retained. The ordering is what guarantees survival: anonymisation nils the
  host reference on each row (`booking_payments.host_user_id` is a bare
  integer with no FK; `payment_transactions.user_id` is set to nil) before the
  user row is deleted, so no retained row still points at the user when the
  delete runs — regardless of the FK's `on_delete`. Both must happen in the
  same transaction. Required for tax-record retention under EU and Swiss
  commercial law (GDPR Art. 17(3)(b) carve-out). The user's still-pending
  Oban jobs are deleted in the same transaction.

  Once the transaction commits, every live socket bound to one of the user's
  sessions is disconnected: the cascade removes the session rows, but a
  connected LiveView socket never re-reads them.

  Then the profile's uploaded avatars and theme
  backgrounds are removed from disk. The database cascade deletes only rows,
  and an avatar is usually a photo of the person, so leaving the files would
  keep personal data past an erasure request. Files go only after the commit:
  a rolled-back deletion must not leave live rows pointing at missing files.
  A file that cannot be removed is logged and does not fail the deletion,
  which has already happened.

  `context` (the actor and the `prepare/1` summary) goes into the audit log.
  """
  @spec purge(UserSchema.t(), map()) ::
          {:ok, UserSchema.t()} | {:error, Ecto.Changeset.t() | term()}
  def purge(%UserSchema{} = user, context \\ %{}) do
    # Resolved before the delete: the cascade removes the row that knows it.
    profile = Profiles.get_profile(user.id)

    user.id
    |> run_deletion_transaction(user)
    |> log_transaction_failure(user.id)
    |> disconnect_sessions()
    |> delete_uploaded_files(profile)
    |> log_deleted(context)
  end

  @doc """
  Deletes a user in one go: the external-cleanup hook, then `purge/2`.

  If the hook fails, the deletion is aborted and the user, along with all
  their data, is left intact. Does not cancel upcoming meetings — use
  `request/2` for a deletion the user's invitees must hear about.
  """
  @spec delete_account(UserSchema.t()) ::
          {:ok, UserSchema.t()} | {:error, Ecto.Changeset.t() | term()}
  def delete_account(%UserSchema{} = user) do
    with :ok <- run_account_deletion_hook(user.id) do
      purge(user, %{actor: :system})
    end
  end

  # The session rows go with the user by FK cascade; their hashes are read
  # first, inside the same transaction, so the live sockets bound to them can
  # be told to disconnect once the deletion has committed.
  defp run_deletion_transaction(user_id, user) do
    Repo.transaction(fn ->
      session_hashes = UserSessionQueries.list_user_session_token_hashes(user_id)

      with :ok <- MeetingPayments.anonymise_host(user_id),
           {_deleted_jobs, nil} <-
             ObanJobQueries.delete_pending_jobs_for_user(user_id, AccountDeletionWorker),
           {:ok, deleted} <- UserQueries.delete_user_row(user) do
        {deleted, session_hashes}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # Only after the commit: a rolled-back deletion must leave its sessions
  # connected.
  defp disconnect_sessions({:ok, {deleted, session_hashes}}) do
    Enum.each(session_hashes, &Session.disconnect_session_hash/1)
    {:ok, deleted}
  end

  defp disconnect_sessions(error), do: error

  defp log_transaction_failure({:error, reason} = error, user_id) do
    Logger.error(
      "Account deletion DB transaction failed after the external deletion hook already ran " <>
        "(a subscription may have been cancelled). Manual reconciliation required.",
      user_id: user_id,
      reason: LogFormat.reason(reason)
    )

    error
  end

  defp log_transaction_failure(result, _user_id), do: result

  defp delete_uploaded_files({:ok, deleted} = result, %{id: profile_id}) do
    for {kind, outcome} <- [
          avatars: Profiles.delete_avatar_files(profile_id),
          theme_backgrounds: ThemeCustomizations.delete_profile_files(profile_id),
          booking_attachments: AttendeeAttachments.delete_user_files(deleted.id)
        ],
        outcome != :ok do
      {:error, reason, path} = outcome

      Logger.error(
        "Account deleted but its uploaded files could not be removed; delete them by hand",
        user_id: deleted.id,
        profile_id: profile_id,
        files: kind,
        path: path,
        reason: LogFormat.reason(reason)
      )
    end

    result
  end

  defp delete_uploaded_files(result, _profile), do: result

  defp log_deleted({:ok, deleted} = result, context) do
    {actor, summary} = Map.pop(context, :actor, :system)
    log_success("account_deletion", deleted.id, actor, summary)
    result
  end

  defp log_deleted(result, _context), do: result

  # `AccountLogging` puts the actor and the summary on the log line (its
  # context becomes Logger metadata); `SecurityLogger` records the event in the
  # audit log, the summary going into the event's metadata.
  defp log_success(operation, user_id, actor, extra) do
    {actor_kind, actor_user_id} = describe_actor(actor, user_id)

    AccountLogging.log_operation_success(
      operation,
      user_id,
      Map.merge(extra, %{target_user_id: user_id, actor: actor_kind, actor_user_id: actor_user_id})
    )

    SecurityLogger.log_security_event("#{operation}_success", %{
      user_id: user_id,
      actor_user_id: actor_user_id,
      additional_data: Map.put(extra, :actor, actor_kind)
    })
  end

  defp describe_actor(:self, user_id), do: {"self", user_id}
  defp describe_actor({:admin, admin_id}, _user_id), do: {"admin", admin_id}
  defp describe_actor(:system, _user_id), do: {"system", nil}

  # A daily run deletes at most this many, so a sign-up flood cannot turn one
  # run into an unbounded loop of deletions; the rest go on the following days.
  @purge_batch_size 500

  @doc """
  Deletes accounts still unverified `days` after sign-up, through
  `delete_account/1`, so each goes exactly as an erasure request would.

  An unverified account cannot sign in, so after a month it is an abandoned
  sign-up, or one made with somebody else's address, holding an email
  address and the IP it was registered from. An account sent a fresh
  verification link within the window is spared. At most #{@purge_batch_size}
  are deleted per call, and none for a `days` below one.

  Returns `{deleted_count, nil}`, the shape `Tymeslot.Workers.DataRetentionWorker`
  expects of a prune function.
  """
  @spec purge_unverified_accounts(integer()) :: {non_neg_integer(), nil}
  def purge_unverified_accounts(days) when is_integer(days) and days > 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -days, :day)

    deleted =
      cutoff
      |> UserQueries.list_stale_unverified_users(@purge_batch_size)
      |> Enum.count(&purged?/1)

    {deleted, nil}
  end

  # A zero or negative window would select every unverified account, however
  # new: the retention worker passes such values through from job args, and
  # they must delete nothing.
  def purge_unverified_accounts(_days), do: {0, nil}

  defp purged?(user) do
    case delete_account(user) do
      {:ok, _deleted} ->
        true

      {:error, reason} ->
        Logger.error("Could not purge an unverified account",
          user_id: user.id,
          reason: LogFormat.reason(reason)
        )

        false
    end
  end

  defp run_account_deletion_hook(user_id) do
    case Application.get_env(:tymeslot, :account_deletion_hook) do
      nil -> :ok
      hook -> hook.on_account_deletion(user_id)
    end
  end
end
