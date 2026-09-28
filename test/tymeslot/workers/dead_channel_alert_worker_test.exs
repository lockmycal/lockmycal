defmodule Tymeslot.Workers.DeadChannelAlertWorkerTest do
  use Tymeslot.DataCase, async: true
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :workers
  @moduletag :calendar

  import Tymeslot.AdminAlertsCaptureHelpers
  import Tymeslot.Factory

  alias Tymeslot.Workers.DeadChannelAlertWorker

  setup :capture_admin_alerts

  describe "perform/1" do
    test "raises no alert when the database holds no integrations" do
      assert :ok = perform_job(DeadChannelAlertWorker, %{})

      refute_received {:send_alert, :dead_webhook_channel, _payload}
    end

    test "flags a silent google integration that has a recent confirmed meeting" do
      user = silent_google_integration()

      assert :ok = perform_job(DeadChannelAlertWorker, %{})

      assert_received {:send_alert, :dead_webhook_channel, payload}
      assert payload.user_id == user.id
      assert payload.provider == "google"
      refute_received {:send_alert, :dead_webhook_channel, _other}
    end

    test "does not flag a google integration that received a recent notification" do
      flagged = silent_google_integration()
      quiet = insert(:user)

      quiet
      |> google_integration(last_google_notification_at: DateTime.utc_now())
      |> confirmed_meeting(quiet)

      assert :ok = perform_job(DeadChannelAlertWorker, %{})

      assert_received {:send_alert, :dead_webhook_channel, payload}
      assert payload.user_id == flagged.id
      refute_received {:send_alert, :dead_webhook_channel, _other}
    end

    test "does not flag a google integration with an expired channel" do
      flagged = silent_google_integration()
      quiet = insert(:user)

      quiet
      |> google_integration(google_channel_expires_at: DateTime.add(DateTime.utc_now(), -3_600))
      |> confirmed_meeting(quiet)

      assert :ok = perform_job(DeadChannelAlertWorker, %{})

      assert_received {:send_alert, :dead_webhook_channel, payload}
      assert payload.user_id == flagged.id
      refute_received {:send_alert, :dead_webhook_channel, _other}
    end

    test "does not flag a google integration that never had a channel id" do
      flagged = silent_google_integration()
      quiet = insert(:user)

      quiet
      |> google_integration(google_channel_id: nil, google_channel_expires_at: nil)
      |> confirmed_meeting(quiet)

      assert :ok = perform_job(DeadChannelAlertWorker, %{})

      assert_received {:send_alert, :dead_webhook_channel, payload}
      assert payload.user_id == flagged.id
      refute_received {:send_alert, :dead_webhook_channel, _other}
    end

    test "does not flag a google integration without a recent confirmed meeting" do
      flagged = silent_google_integration()
      quiet = insert(:user)
      google_integration(quiet, [])

      assert :ok = perform_job(DeadChannelAlertWorker, %{})

      assert_received {:send_alert, :dead_webhook_channel, payload}
      assert payload.user_id == flagged.id
      refute_received {:send_alert, :dead_webhook_channel, _other}
    end

    test "flags a silent outlook subscription and ignores one without a subscription id" do
      flagged = insert(:user)

      flagged
      |> outlook_integration([])
      |> confirmed_meeting(flagged)

      quiet = insert(:user)

      quiet
      |> outlook_integration(graph_subscription_id: nil, graph_subscription_expires_at: nil)
      |> confirmed_meeting(quiet)

      assert :ok = perform_job(DeadChannelAlertWorker, %{})

      assert_received {:send_alert, :dead_webhook_channel, payload}
      assert payload.user_id == flagged.id
      assert payload.provider == "outlook"
      refute_received {:send_alert, :dead_webhook_channel, _other}
    end
  end

  defp silent_google_integration do
    user = insert(:user)

    user
    |> google_integration([])
    |> confirmed_meeting(user)

    user
  end

  defp google_integration(user, overrides) do
    defaults = [
      user: user,
      provider: "google",
      is_active: true,
      google_channel_id: unique_id("channel"),
      google_channel_expires_at: DateTime.add(DateTime.utc_now(), 7 * 86_400),
      last_google_notification_at: DateTime.add(DateTime.utc_now(), -48 * 3_600)
    ]

    insert(:calendar_integration, Keyword.merge(defaults, overrides))
  end

  defp outlook_integration(user, overrides) do
    defaults = [
      user: user,
      provider: "outlook",
      is_active: true,
      graph_subscription_id: unique_id("subscription"),
      graph_subscription_expires_at: DateTime.add(DateTime.utc_now(), 2 * 86_400),
      last_outlook_notification_at: DateTime.add(DateTime.utc_now(), -48 * 3_600)
    ]

    insert(:calendar_integration, Keyword.merge(defaults, overrides))
  end

  defp confirmed_meeting(integration, user) do
    insert(:meeting,
      organizer_user_id: user.id,
      calendar_integration_id: integration.id,
      start_time: DateTime.truncate(DateTime.add(DateTime.utc_now(), -24 * 3_600), :second),
      end_time: DateTime.truncate(DateTime.add(DateTime.utc_now(), -23 * 3_600), :second),
      status: "confirmed"
    )
  end

  defp unique_id(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"
end
