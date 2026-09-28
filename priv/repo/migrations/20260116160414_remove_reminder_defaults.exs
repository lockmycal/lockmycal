defmodule Tymeslot.Repo.Migrations.RemoveReminderDefaults do
  use Ecto.Migration

  def change do
    alter table(:meeting_types) do
      modify :reminder_config, {:array, :map}, default: nil
    end

    alter table(:meetings) do
      modify :reminders, {:array, :map}, default: nil
      modify :reminders_sent, {:array, :map}, default: nil
    end
  end
end
