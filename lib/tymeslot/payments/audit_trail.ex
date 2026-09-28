defmodule Tymeslot.Payments.AuditTrail do
  @moduledoc """
  Records subscription payment events (paid, failed, expired checkout,
  failed charge, refunds, disputes) from the platform Stripe account in the
  audit log (`Tymeslot.Security.AuditLog`, category
  `"subscription_payments"`).

  Every event is about the subscribing user, resolved from the Stripe
  customer where the event does not name them (`nil` when nothing
  resolves: the event is still recorded, with the customer id). Only ids,
  amounts and Stripe's own statuses and reasons are recorded.
  """

  alias Tymeslot.Payments.CustomerLookup
  alias Tymeslot.Payments.PaymentTransactionSchema
  alias Tymeslot.Payments.Webhooks.InvoiceEvent
  alias Tymeslot.Security.AuditLog

  @doc "The first payment of a subscription cleared in its checkout."
  @spec checkout_paid(map(), integer() | nil) :: :ok
  def checkout_paid(session, user_id) do
    record("subscription_payment_paid", user_id, %{
      checkout_session_id: session["id"],
      subscription_id: session["subscription"],
      amount_cents: session["amount_total"],
      currency: session["currency"]
    })
  end

  @doc "A renewal invoice was paid."
  @spec invoice_paid(InvoiceEvent.t(), integer() | nil) :: :ok
  def invoice_paid(%InvoiceEvent{} = event, user_id) do
    record("subscription_payment_paid", user_id, invoice_metadata(event, event.amount_paid))
  end

  @doc "A subscription invoice could not be charged."
  @spec invoice_failed(InvoiceEvent.t(), integer() | nil, integer() | nil) :: :ok
  def invoice_failed(%InvoiceEvent{} = event, user_id, attempt_count) do
    record(
      "subscription_payment_failed",
      user_id,
      Map.put(invoice_metadata(event, event.amount_cents), :attempt_count, attempt_count)
    )
  end

  @doc "A subscription checkout lapsed without being paid."
  @spec checkout_expired(PaymentTransactionSchema.t()) :: :ok
  def checkout_expired(transaction) do
    record("subscription_checkout_expired", transaction.user_id, %{
      checkout_session_id: transaction.stripe_id,
      amount_cents: transaction.amount
    })
  end

  @doc "Stripe declined a charge (`charge.failed`)."
  @spec charge_failed(map()) :: :ok
  def charge_failed(charge) do
    record_for_customer("subscription_charge_failed", charge["customer"], %{
      charge_id: charge["id"],
      amount_cents: charge["amount"],
      currency: charge["currency"],
      failure_code: charge["failure_code"],
      failure_message: charge["failure_message"]
    })
  end

  @doc "A refund was issued on a platform charge (`charge.refunded`)."
  @spec refund_issued(integer() | nil, map()) :: :ok
  def refund_issued(user_id, metadata),
    do: record("subscription_refund_issued", user_id, metadata)

  @doc "A chargeback was opened on a platform charge."
  @spec dispute_opened(map(), String.t() | nil) :: :ok
  def dispute_opened(dispute, customer_id) do
    record_for_customer("subscription_dispute_opened", customer_id, %{
      dispute_id: dispute["id"],
      charge_id: dispute["charge"],
      disputed_cents: dispute["amount"],
      currency: dispute["currency"],
      reason: dispute["reason"]
    })
  end

  @doc "A chargeback on a platform charge was decided (`won`, `lost`, ...)."
  @spec dispute_closed(map(), String.t() | nil) :: :ok
  def dispute_closed(dispute, customer_id) do
    record_for_customer("subscription_dispute_closed", customer_id, %{
      dispute_id: dispute["id"],
      charge_id: dispute["charge"],
      disputed_cents: dispute["amount"],
      currency: dispute["currency"],
      outcome: dispute["status"]
    })
  end

  @doc "The user a Stripe customer belongs to, or `nil`."
  @spec user_for_customer(String.t() | nil) :: integer() | nil
  def user_for_customer(nil), do: nil

  def user_for_customer(customer_id),
    do: CustomerLookup.find_user_id(%{subscription_id: nil, customer_id: customer_id})

  defp invoice_metadata(event, amount_cents) do
    %{
      invoice_id: event.id,
      subscription_id: event.subscription_id,
      billing_reason: event.billing_reason,
      amount_cents: amount_cents,
      currency: event.currency
    }
  end

  defp record_for_customer(event_type, customer_id, metadata) do
    record(
      event_type,
      user_for_customer(customer_id),
      Map.put(metadata, :customer_id, customer_id)
    )
  end

  defp record(event_type, user_id, metadata) do
    AuditLog.record_event(event_type, %{user_id: user_id, metadata: metadata})
  end
end
