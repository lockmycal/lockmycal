defmodule Tymeslot.MeetingPayments.AuditTrailTest do
  @moduledoc """
  Booking payment events reach the audit log from the flows that change the
  payment: Connect webhooks and refunds issued from the app.
  """

  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :payments
  @moduletag :integration

  import Mox
  import Tymeslot.AppSettingsEnvHelpers, only: [restore_app_settings_env: 1]
  import Tymeslot.Factory

  alias Tymeslot.AppSettings
  alias Tymeslot.MeetingPayments.Refunds
  alias Tymeslot.MeetingPayments.StripeAdapterMock
  alias Tymeslot.MeetingPayments.Webhooks.ChargeDisputeClosed
  alias Tymeslot.MeetingPayments.Webhooks.ChargeDisputeCreated
  alias Tymeslot.MeetingPayments.Webhooks.ChargeRefunded
  alias Tymeslot.MeetingPayments.Webhooks.CheckoutSessionAsyncPaymentFailed
  alias Tymeslot.MeetingPayments.Webhooks.CheckoutSessionCompleted
  alias Tymeslot.MeetingPayments.Webhooks.CheckoutSessionExpired
  alias Tymeslot.Repo
  alias Tymeslot.Security.AuditLog.AuditEventSchema

  setup :verify_on_exit!
  setup :restore_app_settings_env

  defp audit_events, do: Repo.all(from(e in AuditEventSchema, order_by: e.id))

  defp event(type, object) do
    %{
      "id" => "evt_#{System.unique_integer([:positive])}",
      "type" => type,
      "created" => System.os_time(:second),
      "data" => %{"object" => object}
    }
  end

  defp pending_payment do
    meeting = insert(:meeting, status: "awaiting_payment")
    session_id = "cs_#{System.unique_integer([:positive])}"
    payment = insert(:booking_payment, meeting: meeting, stripe_checkout_session_id: session_id)
    {payment, %{"id" => session_id, "client_reference_id" => meeting.id}}
  end

  test "a paid checkout is recorded against the host" do
    {payment, session} = pending_payment()

    session = Map.merge(session, %{"payment_intent" => "pi_1", "payment_status" => "paid"})
    assert :ok = CheckoutSessionCompleted.handle(event("checkout.session.completed", session))

    assert [audit] = audit_events()
    assert audit.event_type == "booking_payment_paid"
    assert audit.user_id == payment.host_user_id

    assert %{
             "booking_payment_id" => id,
             "amount_cents" => 5000,
             "currency" => "eur",
             "recovered_after_expiry" => false
           } = audit.metadata

    assert id == payment.id
  end

  test "an expired checkout and a failed delayed payment are told apart" do
    {expired, expired_session} = pending_payment()
    {failed, failed_session} = pending_payment()

    assert :ok = CheckoutSessionExpired.handle(event("checkout.session.expired", expired_session))

    assert :ok =
             CheckoutSessionAsyncPaymentFailed.handle(
               event("checkout.session.async_payment_failed", failed_session)
             )

    assert [
             %{event_type: "booking_payment_expired", user_id: expired_host},
             %{event_type: "booking_payment_failed", user_id: failed_host}
           ] = audit_events()

    assert expired_host == expired.host_user_id
    assert failed_host == failed.host_user_id
  end

  test "a host's refund records the host as actor; a failed one records Stripe's reason" do
    payment = insert(:paid_booking_payment)

    expect(StripeAdapterMock, :create_refund, fn _params, _opts -> {:ok, %{id: "re_1"}} end)

    expect(StripeAdapterMock, :create_refund, fn _params, _opts ->
      {:error, %{message: "Charge already refunded"}}
    end)

    assert {:ok, _payment} = Refunds.issue_host_refund(payment.id, payment.host_user_id, 1000)
    assert {:error, _reason} = Refunds.issue_host_refund(payment.id, payment.host_user_id, 1000)

    assert [issued, failed] = audit_events()

    assert issued.event_type == "booking_refund_issued"
    assert issued.actor_user_id == payment.host_user_id

    assert %{"refunded_cents" => 1000, "source" => "app", "status" => "partially_refunded"} =
             issued.metadata

    assert failed.event_type == "booking_refund_failed"
    assert failed.user_id == payment.host_user_id
    assert %{"reason" => "Charge already refunded", "amount_cents" => 1000} = failed.metadata
  end

  test "a refund attempt on another host's payment leaves no trace" do
    payment = insert(:paid_booking_payment)

    assert {:error, :not_found} = Refunds.issue_host_refund(payment.id, -1, 1000)
    assert audit_events() == []
  end

  test "charge.refunded records only a refund issued outside the app" do
    payment = insert(:paid_booking_payment, refunded_amount_cents: 1000)

    refunded =
      &event("charge.refunded", %{"id" => payment.stripe_charge_id, "amount_refunded" => &1})

    # Reconciles the refund the app already recorded.
    assert :ok = ChargeRefunded.handle(refunded.(1000))
    assert audit_events() == []

    assert :ok = ChargeRefunded.handle(refunded.(3000))

    assert [%{event_type: "booking_refund_issued", metadata: metadata}] = audit_events()

    assert %{"refunded_cents" => 2000, "refunded_total_cents" => 3000, "source" => "stripe"} =
             metadata
  end

  test "a dispute is recorded when opened and when closed" do
    payment = insert(:paid_booking_payment)
    dispute = %{"charge" => payment.stripe_charge_id, "amount" => 5000}

    assert :ok =
             ChargeDisputeCreated.handle(
               event("charge.dispute.created", Map.put(dispute, "reason", "fraudulent"))
             )

    assert :ok =
             ChargeDisputeClosed.handle(
               event("charge.dispute.closed", Map.put(dispute, "status", "lost"))
             )

    assert [opened, closed] = audit_events()
    assert %{"reason" => "fraudulent", "disputed_cents" => 5000} = opened.metadata
    assert closed.event_type == "booking_dispute_closed"
    assert %{"outcome" => "lost"} = closed.metadata
  end

  test "nothing is recorded while the category is switched off" do
    {:ok, _settings} = AppSettings.update(%{audit_log_events: %{"booking_payments" => false}})
    {_payment, session} = pending_payment()

    assert :ok = CheckoutSessionExpired.handle(event("checkout.session.expired", session))
    assert audit_events() == []
  end
end
