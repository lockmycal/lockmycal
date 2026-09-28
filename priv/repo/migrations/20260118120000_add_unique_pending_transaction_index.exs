defmodule Tymeslot.Repo.Migrations.AddUniquePendingTransactionIndex do
  use Ecto.Migration

  def change do
    # Add a unique index to ensure only one pending transaction per user exists
    # This prevents race conditions in initiate_payment
    create unique_index(:payment_transactions, [:user_id],
             where: "status = 'pending'",
             name: :unique_pending_transaction_per_user
           )
  end
end
