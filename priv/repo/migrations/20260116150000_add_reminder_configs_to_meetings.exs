defmodule Tymeslot.Repo.Migrations.AddReminderConfigsToMeetings do
  use Ecto.Migration

  def change do
    alter table(:meeting_types) do
      add :reminder_config, {:array, :map}
    end

    alter table(:meetings) do
      add :reminders, {:array, :map}
      add :reminders_sent, {:array, :map}
    end
  end
end
