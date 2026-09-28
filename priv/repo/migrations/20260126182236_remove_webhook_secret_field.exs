defmodule Tymeslot.Repo.Migrations.RemoveWebhookSecretField do
  use Ecto.Migration

  def change do
    alter table(:webhooks) do
      remove :secret_encrypted, :binary
    end
  end
end
