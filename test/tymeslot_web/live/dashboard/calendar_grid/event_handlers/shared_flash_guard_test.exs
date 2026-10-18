defmodule TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.SharedFlashGuardTest do
  @moduledoc """
  `Shared.flash_guard_error/2` answers every guard error the event handlers
  pass it, including `check_seat_lock/2`'s `{:error, :group_booking}` — a
  missing clause there crashed the calendar grid on any change to a group
  booking.
  """

  use ExUnit.Case, async: true

  @moduletag :unit
  @moduletag :calendar

  alias TymeslotWeb.Dashboard.CalendarGrid.EventHandlers.Shared

  @socket %Phoenix.LiveView.Socket{}

  describe "flash_guard_error/2" do
    test "refuses a change to a group booking with the seat-lock message" do
      assert {:noreply, @socket} = Shared.flash_guard_error(@socket, {:error, :group_booking})

      message = Shared.seat_lock_message()
      assert_received {:flash, {:warning, ^message}}
    end

    test "answers each of the other guard errors with a flash" do
      for error <- [
            {:error, :unauthorized},
            {:error, :read_only},
            {:error, :rate_limited, "slow down"},
            {:error, :until_before_start}
          ] do
        assert {:noreply, @socket} = Shared.flash_guard_error(@socket, error)
        assert_received {:flash, {_level, message}} when is_binary(message)
      end
    end
  end
end
