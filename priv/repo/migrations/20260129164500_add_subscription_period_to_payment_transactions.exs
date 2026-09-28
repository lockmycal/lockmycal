defmodule Tymeslot.Repo.Migrations.AddSubscriptionPeriodToPaymentTransactions do
  use Ecto.Migration

  def up do
    execute("""
    ALTER TABLE payment_transactions
    ADD COLUMN IF NOT EXISTS subscription_period varchar
    """)
  end

  def down do
    execute("""
    ALTER TABLE payment_transactions
    DROP COLUMN IF EXISTS subscription_period
    """)
  end
end
