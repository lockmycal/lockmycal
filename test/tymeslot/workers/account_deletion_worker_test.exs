defmodule Tymeslot.Workers.AccountDeletionWorkerTest do
  @moduledoc """
  The background half of a requested account deletion: `"prepare"` cancels
  the user's upcoming meetings through the ordinary cancel flow (so every
  invitee is told and refunded) and hands over to `"purge"`, which waits for
  the notifications that queued before deleting the rows they read.
  """

  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :workers
  @moduletag :auth
  @moduletag :meetings

  import Mox
  import Tymeslot.MeetingTestHelpers

  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Integrations.Calendar.TokenRefreshJob
  alias Tymeslot.Integrations.Video.VideoIntegrationQueries
  alias Tymeslot.MeetingPayments.StripeAdapterMock
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.TestMocks
  alias Tymeslot.Workers.AccountDeletionWorker
  alias Tymeslot.Workers.EmailWorker
  alias Tymeslot.Workers.IntegrationHealthWorker
  alias Tymeslot.Workers.VideoIntegrationDisconnectWorker

  setup :verify_on_exit!

  defmodule FailingHook do
    @behaviour Tymeslot.Auth.Behaviours.AccountDeletionHook
    @impl Tymeslot.Auth.Behaviours.AccountDeletionHook
    def on_account_deletion(_user_id), do: {:error, :subscription_cancel_failed}
  end

  setup do
    TestMocks.setup_email_mocks()
    %{user: user} = create_user_with_profile()
    {:ok, user: user}
  end

  defp prepare_args(user), do: %{"user_id" => user.id, "step" => "prepare", "actor" => "self"}
  defp purge_args(user), do: %{"user_id" => user.id, "step" => "purge", "actor" => "self"}

  describe "prepare" do
    test "cancels upcoming meetings, leaves past ones, and schedules the purge", %{user: user} do
      upcoming = insert_meeting_for_user(user, %{start_offset: 2 * 86_400})
      past = insert_meeting_for_user(user, %{start_offset: -2 * 86_400, status: "completed"})

      assert :ok = perform_job(AccountDeletionWorker, prepare_args(user))

      assert Repo.get!(MeetingSchema, upcoming.id).status == "cancelled"
      assert Repo.get!(MeetingSchema, past.id).status == "completed"

      assert_enqueued(
        worker: EmailWorker,
        args: %{"action" => "send_cancellation_emails", "meeting_id" => upcoming.id}
      )

      assert_enqueued(
        worker: AccountDeletionWorker,
        args: %{"user_id" => user.id, "step" => "purge", "meetings_cancelled" => 1}
      )
    end

    test "refunds a paid upcoming meeting", %{user: user} do
      meeting = insert_meeting_for_user(user, %{start_offset: 3 * 86_400})

      payment =
        insert(:paid_booking_payment,
          meeting_id: meeting.id,
          host_user_id: user.id,
          host_email: user.email
        )

      expect(StripeAdapterMock, :create_refund, fn params, _opts ->
        assert params.charge == payment.stripe_charge_id
        assert params.amount == payment.amount_cents
        {:ok, %{id: "re_account_deletion"}}
      end)

      assert :ok = perform_job(AccountDeletionWorker, prepare_args(user))

      assert Repo.get!(MeetingSchema, meeting.id).status == "cancelled"

      assert_enqueued(
        worker: AccountDeletionWorker,
        args: %{"step" => "purge", "meetings_cancelled" => 1, "manual_refunds" => []}
      )
    end

    test "a failed refund still cancels the meeting and is recorded for a manual refund", %{
      user: user
    } do
      meeting = insert_meeting_for_user(user, %{start_offset: 3 * 86_400})

      payment =
        insert(:paid_booking_payment,
          meeting_id: meeting.id,
          host_user_id: user.id,
          host_email: user.email
        )

      expect(StripeAdapterMock, :create_refund, fn _params, _opts ->
        {:error, %Stripe.Error{source: :stripe, code: :card_error, message: "boom"}}
      end)

      assert :ok = perform_job(AccountDeletionWorker, prepare_args(user))

      assert Repo.get!(MeetingSchema, meeting.id).status == "cancelled"

      assert_enqueued(
        worker: AccountDeletionWorker,
        args: %{"step" => "purge", "manual_refunds" => [payment.id]}
      )
    end

    test "a failing deletion hook returns an error and touches nothing", %{user: user} do
      Application.put_env(:tymeslot, :account_deletion_hook, FailingHook)
      on_exit(fn -> Application.delete_env(:tymeslot, :account_deletion_hook) end)

      meeting = insert_meeting_for_user(user, %{start_offset: 2 * 86_400})

      assert {:error, :subscription_cancel_failed} =
               perform_job(AccountDeletionWorker, prepare_args(user))

      assert Repo.get!(MeetingSchema, meeting.id).status == "confirmed"
      refute_enqueued(worker: AccountDeletionWorker, args: %{"step" => "purge"})
    end

    test "is a no-op for a user that no longer exists" do
      assert :ok =
               perform_job(AccountDeletionWorker, %{"user_id" => -1, "step" => "prepare"})
    end
  end

  describe "prepare and video rooms that outlive their meeting" do
    test "disconnects a Nextcloud Talk integration with its rooms, and only that one", %{
      user: user
    } do
      talk = insert(:video_integration, user: user, provider: "nextcloud_talk")
      mirotalk = insert(:video_integration, user: user, provider: "mirotalk")

      assert :ok = perform_job(AccountDeletionWorker, prepare_args(user))

      assert VideoIntegrationQueries.deleted_for_user?(user.id)
      assert %{deleted_at: %DateTime{}} = Repo.reload!(talk)
      assert %{deleted_at: nil} = Repo.reload!(mirotalk)

      assert_enqueued(
        worker: VideoIntegrationDisconnectWorker,
        args: %{"integration_id" => talk.id}
      )

      refute_enqueued(
        worker: VideoIntegrationDisconnectWorker,
        args: %{"integration_id" => mirotalk.id}
      )
    end
  end

  describe "purge" do
    test "waits while a video integration's rooms are still being deleted", %{user: user} do
      insert(:video_integration,
        user: user,
        provider: "nextcloud_talk",
        is_active: false,
        deleted_at: DateTime.utc_now(:second)
      )

      assert {:snooze, _seconds} = perform_job(AccountDeletionWorker, purge_args(user))
      assert Repo.get(UserSchema, user.id)
    end

    test "goes ahead after the wait cap even if a video integration is still draining", %{
      user: user
    } do
      insert(:video_integration,
        user: user,
        provider: "nextcloud_talk",
        is_active: false,
        deleted_at: DateTime.utc_now(:second)
      )

      long_ago = DateTime.add(DateTime.utc_now(), -25 * 3600, :second)

      assert :ok = perform_job(AccountDeletionWorker, purge_args(user), inserted_at: long_ago)
      refute Repo.get(UserSchema, user.id)
    end

    test "waits while a cancellation email for the user's meeting is still queued", %{
      user: user
    } do
      meeting = insert_meeting_for_user(user, %{start_offset: 2 * 86_400})

      {:ok, _job} =
        %{"action" => "send_cancellation_emails", "meeting_id" => meeting.id}
        |> EmailWorker.new()
        |> Oban.insert()

      assert {:snooze, _seconds} = perform_job(AccountDeletionWorker, purge_args(user))
      assert Repo.get(UserSchema, user.id)
    end

    test "goes ahead after the wait cap, deleting the user and their leftover jobs", %{
      user: user
    } do
      meeting = insert_meeting_for_user(user, %{start_offset: 2 * 86_400})

      {:ok, _job} =
        %{"action" => "send_cancellation_emails", "meeting_id" => meeting.id}
        |> EmailWorker.new()
        |> Oban.insert()

      long_ago = DateTime.add(DateTime.utc_now(), -25 * 3600, :second)

      assert :ok =
               perform_job(AccountDeletionWorker, purge_args(user), inserted_at: long_ago)

      refute Repo.get(UserSchema, user.id)
      refute Repo.get(MeetingSchema, meeting.id)
      refute_enqueued(worker: EmailWorker, args: %{"meeting_id" => meeting.id})
    end

    test "deletes the user and their meeting history once nothing is pending", %{user: user} do
      past = insert_meeting_for_user(user, %{start_offset: -2 * 86_400, status: "completed"})

      assert :ok = perform_job(AccountDeletionWorker, purge_args(user))

      refute Repo.get(UserSchema, user.id)
      refute Repo.get(MeetingSchema, past.id)
    end

    test "deletes the user's own queued jobs of every kind", %{user: user} do
      calendar = insert(:calendar_integration, user: user)

      {:ok, _user_job} = Oban.insert(EmailWorker.new(%{"action" => "x", "user_id" => user.id}))

      {:ok, _integration_job} =
        Oban.insert(
          EmailWorker.new(%{"action" => "x", "calendar_integration_id" => calendar.id},
            schedule_in: 86_400
          )
        )

      assert :ok = perform_job(AccountDeletionWorker, purge_args(user))

      assert [] = all_enqueued(worker: EmailWorker)
    end

    test "tells calendar and video integration ids apart by worker", %{user: user} do
      video = insert(:video_integration, user: user)
      other_calendar = insert(:calendar_integration)

      {:ok, _video_health} =
        Oban.insert(
          IntegrationHealthWorker.new(%{"type" => "video", "integration_id" => video.id})
        )

      {:ok, _others_refresh} =
        Oban.insert(TokenRefreshJob.new(%{"integration_id" => other_calendar.id}))

      assert :ok = perform_job(AccountDeletionWorker, purge_args(user))

      refute_enqueued(worker: IntegrationHealthWorker)
      assert_enqueued(worker: TokenRefreshJob, args: %{"integration_id" => other_calendar.id})
    end

    test "leaves another user's jobs alone", %{user: user} do
      %{user: other} = create_user_with_profile()
      other_meeting = insert_meeting_for_user(other, %{start_offset: 2 * 86_400})

      {:ok, _job} =
        %{"action" => "send_cancellation_emails", "meeting_id" => other_meeting.id}
        |> EmailWorker.new()
        |> Oban.insert()

      assert :ok = perform_job(AccountDeletionWorker, purge_args(user))

      assert_enqueued(worker: EmailWorker, args: %{"meeting_id" => other_meeting.id})
    end
  end
end
