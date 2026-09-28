defmodule Tymeslot.Payments.AuditTrailTest do
  @moduledoc """
  Subscription payment events from the platform Stripe account reach the
  audit log, attributed to the subscribing user wherever one resolves.
  """

  use Tymeslot.DataCase, async: false

  @moduletag :payments
  @moduletag :integration

  import Mox
  import Tymeslot.Factory

  alias Tymeslot.Payments.Webhooks.ChargeHandler
  alias Tymeslot.Payments.Webhooks.CheckoutSessionExpiredHandler
  alias Tymeslot.Payments.Webhooks.CheckoutSessionHandler
  alias Tymeslot.Payments.Webhooks.DisputeHandler
  alias Tymeslot.Payments.Webhooks.InvoiceHandler
  alias Tymeslot.Payments.Webhooks.RefundHandler
  alias Tymeslot.Security.AuditLog.AuditEventSchema

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    # The test env points :repo at SaasRepo; the factory's transactions live
    # in Tymeslot.Repo, which customer lookups must read.
    for {key, value} <- [
          repo: Tymeslot.Repo,
          stripe_provider: Tymeslot.Payments.StripeMock,
          subscription_manager: Tymeslot.Payments.SubscriptionManagerMock
        ] do
      original = Application.get_env(:tymeslot, key)
      Application.put_env(:tymeslot, key, value)

      on_exit(fn ->
        if original,
          do: Application.put_env(:tymeslot, key, original),
          else: Application.delete_env(:tymeslot, key)
      end)
    end

    :ok
  end

  defp audit_events, do: Repo.all(from(e in AuditEventSchema, order_by: e.id))

  defp subscriber(attrs \\ []) do
    user = insert(:user)

    insert(
      :payment_transaction,
      Keyword.merge(
        [
          user: user,
          status: "completed",
          subscription_id: "sub_#{System.unique_integer([:positive])}",
          stripe_customer_id: "cus_#{System.unique_integer([:positive])}"
        ],
        attrs
      )
    )
  end

  test "a paid first checkout and a paid renewal are recorded" do
    transaction = subscriber()
    user_id = transaction.user_id

    expect(Tymeslot.Payments.SubscriptionManagerMock, :handle_checkout_completed, fn _session ->
      {:ok, %{user_id: user_id}}
    end)

    session = %{
      "id" => "cs_sub",
      "mode" => "subscription",
      "subscription" => transaction.subscription_id,
      "amount_total" => 1200,
      "currency" => "eur"
    }

    assert {:ok, :subscription_processed} = CheckoutSessionHandler.process(%{}, session)

    invoice = %{
      "id" => "in_renewal",
      "subscription" => transaction.subscription_id,
      "billing_reason" => "subscription_cycle",
      "amount_paid" => 1200,
      "total" => 1200,
      "currency" => "eur",
      "status" => "paid"
    }

    assert {:ok, :invoice_processed} = InvoiceHandler.process(%{type: "invoice.paid"}, invoice)

    assert [checkout, renewal] = audit_events()
    assert checkout.event_type == "subscription_payment_paid"
    assert checkout.user_id == user_id
    assert %{"checkout_session_id" => "cs_sub", "amount_cents" => 1200} = checkout.metadata
    assert renewal.user_id == user_id

    assert %{"invoice_id" => "in_renewal", "billing_reason" => "subscription_cycle"} =
             renewal.metadata
  end

  test "a failed invoice is recorded with its attempt count" do
    transaction = subscriber()

    invoice = %{
      "id" => "in_failed",
      "subscription" => transaction.subscription_id,
      "billing_reason" => "subscription_cycle",
      "attempt_count" => 2,
      "total" => 1200,
      "currency" => "eur",
      "created" => 1_234_567_890
    }

    assert {:ok, :invoice_processed} =
             InvoiceHandler.process(%{type: "invoice.payment_failed"}, invoice)

    assert [%{event_type: "subscription_payment_failed", user_id: user_id, metadata: metadata}] =
             audit_events()

    assert user_id == transaction.user_id
    assert %{"attempt_count" => 2, "amount_cents" => 1200, "invoice_id" => "in_failed"} = metadata
  end

  test "an expired subscription checkout is recorded" do
    transaction = insert(:payment_transaction, stripe_id: "cs_lapsed")

    assert {:ok, :event_processed} =
             CheckoutSessionExpiredHandler.process(%{}, %{"id" => "cs_lapsed"})

    assert [%{event_type: "subscription_checkout_expired", user_id: user_id}] = audit_events()
    assert user_id == transaction.user_id
  end

  test "a declined charge is recorded, with the user resolved from the Stripe customer" do
    transaction = subscriber()

    charge = %{
      "id" => "ch_declined",
      "customer" => transaction.stripe_customer_id,
      "amount" => 1200,
      "currency" => "eur",
      "failure_code" => "card_declined",
      "failure_message" => "Your card was declined."
    }

    assert {:ok, :charge_failed_logged} = ChargeHandler.process(%{type: "charge.failed"}, charge)

    assert [%{event_type: "subscription_charge_failed", user_id: user_id, metadata: metadata}] =
             audit_events()

    assert user_id == transaction.user_id
    assert %{"failure_code" => "card_declined", "charge_id" => "ch_declined"} = metadata
  end

  test "a refund with no linked subscription is still recorded, with its customer" do
    charge = %{
      "id" => "ch_orphan",
      "customer" => "cus_orphan",
      "amount" => 1200,
      "amount_refunded" => 1200,
      "currency" => "eur"
    }

    assert {:ok, :refund_logged} =
             RefundHandler.process(%{"id" => "evt_refund", "type" => "charge.refunded"}, charge)

    assert [%{event_type: "subscription_refund_issued", user_id: nil, metadata: metadata}] =
             audit_events()

    assert %{"customer_id" => "cus_orphan", "refunded_total_cents" => 1200} = metadata
  end

  test "a subscription dispute is recorded when opened and when closed" do
    transaction = subscriber()

    stub(Tymeslot.Payments.StripeMock, :get_charge, fn _charge_id ->
      {:ok,
       %{
         "id" => "ch_disputed",
         "customer" => transaction.stripe_customer_id,
         "invoice" => "in_1",
         "subscription" => transaction.subscription_id
       }}
    end)

    dispute = %{
      "id" => "dp_1",
      "charge" => "ch_disputed",
      "amount" => 1200,
      "currency" => "eur",
      "reason" => "fraudulent"
    }

    assert {:ok, _result} =
             DisputeHandler.process(
               %{"id" => "evt_d1", "type" => "charge.dispute.created"},
               Map.put(dispute, "status", "needs_response")
             )

    assert {:ok, _result} =
             DisputeHandler.process(
               %{"id" => "evt_d2", "type" => "charge.dispute.closed"},
               Map.put(dispute, "status", "won")
             )

    assert [opened, closed] = audit_events()
    assert opened.event_type == "subscription_dispute_opened"
    assert opened.user_id == transaction.user_id
    assert %{"reason" => "fraudulent", "disputed_cents" => 1200} = opened.metadata
    assert closed.event_type == "subscription_dispute_closed"
    assert %{"outcome" => "won"} = closed.metadata
  end
end
