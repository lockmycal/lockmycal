defmodule Tymeslot.MeetingPayments.AuditTrail do
  @moduledoc """
  Records booking payment events (paid, failed, expired, refunds, disputes)
  in the audit log (`Tymeslot.Security.AuditLog`, category
  `"booking_payments"`), so an admin can trace what happened to the money
  of a booking after the fact.

  Every event is about the host whose Stripe account took the payment
  (`host_user_id`). Only ids, amounts and Stripe statuses are recorded — no
  attendee name or email: the `booking_payment_id` leads to those while the
  payment row still exists.

  Called after the state change has committed, never inside its
  transaction, so a rolled-back transition leaves no audit row behind.
  """

  alias Tymeslot.MeetingPayments.BookingPaymentSchema
  alias Tymeslot.Security.AuditLog

  @doc "The attendee's payment cleared. `recovered` when it landed after the booking expired."
  @spec paid(BookingPaymentSchema.t(), boolean()) :: :ok
  def paid(payment, recovered) do
    record("booking_payment_paid", payment, %{
      amount_cents: payment.amount_cents,
      recovered_after_expiry: recovered
    })
  end

  @doc """
  The checkout ended without payment: `:webhook_expired` (the session
  lapsed unpaid) or `:webhook_async_payment_failed` (a delayed payment
  method such as a bank debit failed).
  """
  @spec failed(BookingPaymentSchema.t(), atom()) :: :ok
  def failed(payment, :webhook_expired),
    do: record("booking_payment_expired", payment, %{amount_cents: payment.amount_cents})

  def failed(payment, _reason),
    do: record("booking_payment_failed", payment, %{amount_cents: payment.amount_cents})

  @doc """
  A refund went through. `source` is `:app` for one issued from here (by
  `actor_user_id`, or by a system rule when `nil`) and `:stripe` for one
  issued outside it, e.g. in the Stripe dashboard.
  """
  @spec refund_issued(BookingPaymentSchema.t(), pos_integer(), :app | :stripe, integer() | nil) ::
          :ok
  def refund_issued(payment, amount_cents, source, actor_user_id \\ nil) do
    record(
      "booking_refund_issued",
      payment,
      %{
        refunded_cents: amount_cents,
        refunded_total_cents: payment.refunded_amount_cents,
        status: payment.status,
        source: source
      },
      actor_user_id
    )
  end

  @doc """
  A refund attempt from here failed. `context` carries what is known
  without the payment row: `:booking_payment_id`, `:host_user_id` and
  `:actor_user_id`.
  """
  @spec refund_failed(map(), pos_integer() | term(), term()) :: :ok
  def refund_failed(context, amount_cents, reason) do
    AuditLog.record_event("booking_refund_failed", %{
      user_id: context[:host_user_id],
      actor_user_id: context[:actor_user_id],
      metadata: %{
        booking_payment_id: context[:booking_payment_id],
        amount_cents: amount_cents,
        reason: describe(reason)
      }
    })
  end

  @doc "The attendee's bank opened a chargeback."
  @spec dispute_opened(BookingPaymentSchema.t(), map()) :: :ok
  def dispute_opened(payment, dispute) do
    record("booking_dispute_opened", payment, %{
      disputed_cents: dispute["amount"],
      reason: dispute["reason"]
    })
  end

  @doc "A chargeback was decided (`won`, `lost`, ...)."
  @spec dispute_closed(BookingPaymentSchema.t(), map()) :: :ok
  def dispute_closed(payment, dispute) do
    record("booking_dispute_closed", payment, %{
      disputed_cents: dispute["amount"],
      outcome: dispute["status"]
    })
  end

  defp record(event_type, payment, metadata, actor_user_id \\ nil) do
    AuditLog.record_event(event_type, %{
      user_id: payment.host_user_id,
      actor_user_id: actor_user_id,
      metadata:
        Map.merge(
          %{
            booking_payment_id: payment.id,
            meeting_id: payment.meeting_id,
            currency: payment.currency
          },
          metadata
        )
    })
  end

  # Refund errors are atoms from local validation, or a Stripe error / a
  # changeset. Only a Stripe error's message is kept: it is Stripe's own
  # explanation, while an inspected struct could carry request details.
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(%Ecto.Changeset{}), do: "database_update_failed"
  defp describe(%{message: message}) when is_binary(message), do: message
  defp describe(_reason), do: "unknown"
end
