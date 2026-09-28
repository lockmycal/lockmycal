defmodule Tymeslot.Utils.ReminderUtilsTest do
  use Tymeslot.DataCase, async: true

  @moduletag :utils

  alias Tymeslot.Utils.ReminderUtils

  describe "normalize_reminder_string_keys/1" do
    test "normalizes map with string keys" do
      input = %{"value" => "45", "unit" => "minutes"}

      assert {:ok, %{value: 45, unit: "minutes"}} =
               ReminderUtils.normalize_reminder_string_keys(input)
    end

    test "normalizes map with atom keys" do
      input = %{value: 45, unit: "minutes"}

      assert {:ok, %{value: 45, unit: "minutes"}} =
               ReminderUtils.normalize_reminder_string_keys(input)
    end

    test "rejects invalid value" do
      input = %{"value" => "invalid", "unit" => "minutes"}
      assert {:error, :invalid_reminder} = ReminderUtils.normalize_reminder_string_keys(input)
    end

    test "rejects invalid unit" do
      input = %{"value" => "30", "unit" => "decades"}
      assert {:error, :invalid_reminder} = ReminderUtils.normalize_reminder_string_keys(input)
    end
  end

  describe "duplicate_reminders?/1" do
    test "detects duplicates with mixed key types" do
      reminders = [
        %{value: 30, unit: "minutes"},
        %{"value" => 30, "unit" => "minutes"}
      ]

      assert ReminderUtils.duplicate_reminders?(reminders)
    end

    test "returns false for unique reminders" do
      reminders = [
        %{value: 30, unit: "minutes"},
        %{value: 1, unit: "hours"}
      ]

      refute ReminderUtils.duplicate_reminders?(reminders)
    end

    test "is resilient to malformed input" do
      reminders = [
        %{value: 30, unit: "minutes"},
        %{invalid: "data"}
      ]

      # Should not crash, and should consider them unique since the malformed one is ignored
      refute ReminderUtils.duplicate_reminders?(reminders)
    end
  end

  describe "reminder_interval_seconds/2" do
    test "correctly calculates seconds for different units" do
      assert ReminderUtils.reminder_interval_seconds(30, "minutes") == 1800
      assert ReminderUtils.reminder_interval_seconds(1, "hours") == 3600
      assert ReminderUtils.reminder_interval_seconds(2, "days") == 172_800
    end

    test "handles string values and normalization" do
      assert ReminderUtils.reminder_interval_seconds("30", "minutes") == 1800
      assert ReminderUtils.reminder_interval_seconds(1, "hour") == 3600
    end
  end

  describe "from_calendar_reminders/1" do
    test "converts the calendar picker's method/minutes_before shape to value/unit in minutes" do
      reminders = [
        %{method: :popup, minutes_before: 10},
        %{method: :email, minutes_before: 1440}
      ]

      assert ReminderUtils.from_calendar_reminders(reminders) == [
               %{value: 10, unit: "minutes"},
               %{value: 1440, unit: "minutes"}
             ]
    end

    test "drops the method — a meeting's reminders always drive both channels" do
      assert ReminderUtils.from_calendar_reminders([%{method: :email, minutes_before: 5}]) == [
               %{value: 5, unit: "minutes"}
             ]
    end

    test "empty list round-trips to an empty list" do
      assert ReminderUtils.from_calendar_reminders([]) == []
    end

    test "drops a reminder missing minutes_before instead of writing a nil value" do
      assert ReminderUtils.from_calendar_reminders([%{method: :popup}]) == []
    end

    test "drops a zero or negative minutes_before instead of passing it through raw" do
      reminders = [
        %{method: :popup, minutes_before: 0},
        %{method: :popup, minutes_before: -5}
      ]

      assert ReminderUtils.from_calendar_reminders(reminders) == []
    end

    test "keeps the valid entries alongside a dropped invalid one" do
      reminders = [
        %{method: :popup, minutes_before: 10},
        %{method: :popup}
      ]

      assert ReminderUtils.from_calendar_reminders(reminders) == [%{value: 10, unit: "minutes"}]
    end
  end
end
