defmodule Tymeslot.BookingCreateTestHelpers do
  @moduledoc """
  Shared `MockCalendar` agent and setup helpers for `Tymeslot.Bookings.Create`
  tests, split across `Tymeslot.Bookings.CreateTest` and
  `Tymeslot.Bookings.CreateContactCaptureTest`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]
  import Tymeslot.AvailabilityTestHelpers

  # Mock calendar module that can be configured per test
  defmodule MockCalendar do
    @moduledoc """
    Mock calendar module for testing.
    Uses Agent to store test responses.
    """
    use Agent

    @spec start_link() :: {:ok, pid()} | {:error, term()}
    def start_link do
      Agent.start_link(
        fn -> %{response: {:ok, []}, integration_info: {:error, :no_integration}} end,
        name: __MODULE__
      )
    end

    @spec get_events_for_range_fresh(integer(), Date.t(), Date.t()) ::
            {:ok, list()} | {:error, term()} | term()
    def get_events_for_range_fresh(_user_id, _start_date, _end_date) do
      case Agent.get(__MODULE__, & &1.response) do
        {:ok, events} -> {:ok, events}
        {:error, reason} -> {:error, reason}
        other -> other
      end
    end

    @spec get_booking_integration_info(integer() | map()) :: {:ok, map()} | {:error, term()}
    def get_booking_integration_info(_context) do
      Agent.get(__MODULE__, & &1.integration_info)
    end

    @spec set_response(term()) :: :ok
    def set_response(response) do
      Agent.update(__MODULE__, fn state -> %{state | response: response} end)
    end

    @spec set_integration_info(term()) :: :ok
    def set_integration_info(info) do
      Agent.update(__MODULE__, fn state -> %{state | integration_info: info} end)
    end

    @spec stop() :: :ok
    def stop do
      case Process.whereis(__MODULE__) do
        nil ->
          :ok

        _pid ->
          try do
            Agent.stop(__MODULE__)
          catch
            :exit, _reason -> :ok
          end
      end
    end
  end

  @doc "ExUnit `setup` callback: starts MockCalendar and points :calendar_module at it."
  @spec setup_mock_calendar(map()) :: :ok
  def setup_mock_calendar(_context) do
    {:ok, _pid} = MockCalendar.start_link()

    original_module = Application.get_env(:tymeslot, :calendar_module)
    Application.put_env(:tymeslot, :calendar_module, MockCalendar)

    on_exit(fn ->
      MockCalendar.stop()

      if original_module do
        Application.put_env(:tymeslot, :calendar_module, original_module)
      else
        Application.delete_env(:tymeslot, :calendar_module)
      end
    end)

    :ok
  end

  @doc "Shared test setup helper: an always-open host, meeting params, and form data."
  @spec setup_booking_test() :: map()
  def setup_booking_test do
    # An always-open host: these tests are about the calendar conflict check,
    # so the schedule must never be the reason a booking is refused.
    %{user: user} = create_always_bookable_profile(timezone: "America/New_York")

    meeting_params = %{
      date: Date.add(Date.utc_today(), 1),
      time: "14:00",
      duration: "60min",
      user_timezone: "America/New_York",
      organizer_user_id: user.id
    }

    form_data = %{
      "name" => "Test Attendee",
      "email" => "attendee@test.com",
      "message" => "Test message"
    }

    %{user: user, meeting_params: meeting_params, form_data: form_data}
  end

  # Helper functions for MockCalendar responses
  @spec set_calendar_events(list()) :: :ok
  def set_calendar_events(events) do
    MockCalendar.set_response({:ok, events})
  end

  @spec set_calendar_error(term()) :: :ok
  def set_calendar_error(error_type) do
    MockCalendar.set_response({:error, error_type})
  end

  @spec set_calendar_empty() :: :ok
  def set_calendar_empty do
    MockCalendar.set_response({:ok, []})
  end

  @spec create_conflicting_event(map()) :: map()
  def create_conflicting_event(meeting_params) do
    start_time =
      meeting_params.date
      |> DateTime.new!(~T[14:00:00], meeting_params.user_timezone)
      |> DateTime.shift_zone!("Etc/UTC")

    %{
      uid: "conflict-123",
      start_time: start_time,
      end_time: DateTime.add(start_time, 60, :minute)
    }
  end
end
