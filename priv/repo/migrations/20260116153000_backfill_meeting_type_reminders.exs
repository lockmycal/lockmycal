defmodule Tymeslot.Repo.Migrations.BackfillMeetingTypeReminders do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE meeting_types
    SET reminder_config = ARRAY[jsonb_build_object('value', 30, 'unit', 'minutes')]
    WHERE reminder_config IS NULL OR reminder_config = '{}'
    """)
  end

  def down do
    :ok
  end
end
