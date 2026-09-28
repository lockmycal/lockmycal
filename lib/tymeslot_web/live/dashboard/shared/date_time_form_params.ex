defmodule TymeslotWeb.Dashboard.Shared.DateTimeFormParams do
  @moduledoc """
  Parses the native-date/native-time form params sent by the create-event
  dialog's `phx-change="update_create_time"` form into a map's
  date/hour/minute fields — shared by the calendar's own
  `CalendarGrid.EventHandlers.CreateFormState` and the Meetings page's
  `BookingsManagement.QuickAddMeeting`, since both drive the same reused
  dialog (`CalendarGrid.Modals.CreateEventModal`).

  Malformed values are ignored (the field is left unchanged) rather than
  raising, since they come straight from a browser date/time picker.
  """

  @doc "Sets `map[key]` to `date_str` when it parses as a valid ISO-8601 date; otherwise leaves `map` unchanged."
  @spec put_date(map(), String.t() | nil, atom()) :: map()
  def put_date(map, date_str, key) when is_binary(date_str) and date_str != "" do
    case Date.from_iso8601(date_str) do
      {:ok, _date} -> Map.put(map, key, date_str)
      {:error, _reason} -> map
    end
  end

  def put_date(map, _date_str, _key), do: map

  @doc "Sets `map[hour_key]`/`map[minute_key]` from an \"HH:MM\" `time_str`; otherwise leaves `map` unchanged."
  @spec put_time(map(), String.t() | nil, atom(), atom()) :: map()
  def put_time(map, time_str, hour_key, minute_key)
      when is_binary(time_str) and time_str != "" do
    case String.split(time_str, ":") do
      [h, m | _rest] ->
        with {hour, ""} <- Integer.parse(h),
             {minute, ""} <- Integer.parse(m) do
          map
          |> Map.put(hour_key, hour)
          |> Map.put(minute_key, minute)
        else
          _invalid -> map
        end

      _invalid ->
        map
    end
  end

  def put_time(map, _time_str, _hour_key, _minute_key), do: map
end
