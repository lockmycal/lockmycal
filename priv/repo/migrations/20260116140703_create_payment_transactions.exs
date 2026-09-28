defmodule Tymeslot.Repo.Migrations.CreatePaymentTransactions do
  use Ecto.Migration

  def change do
    create table(:payment_transactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false

      # Payment details
      add :amount, :integer, null: false
      add :status, :string, null: false
      add :stripe_id, :string
      add :stripe_customer_id, :string
      add :product_identifier, :string
      add :subscription_id, :string
      add :subscription_period, :string

      # Tax information
      add :tax_amount, :integer
      add :tax_rate, :decimal, precision: 5, scale: 2
      add :discount_amount, :integer
      add :tax_id, :string
      add :is_eu_business, :boolean, default: false
      add :country_code, :string, size: 2
      add :billing_address, :map
      add :payment_method, :string

      # Generic metadata (JSON)
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:payment_transactions, [:user_id])
    create unique_index(:payment_transactions, [:stripe_id])
    create index(:payment_transactions, [:status])
    create index(:payment_transactions, [:product_identifier])
    create index(:payment_transactions, [:inserted_at])
    create index(:payment_transactions, [:subscription_id])
  end
end
