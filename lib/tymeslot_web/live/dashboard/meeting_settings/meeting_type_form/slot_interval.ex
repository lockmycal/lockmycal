defmodule TymeslotWeb.Dashboard.MeetingSettings.MeetingTypeForm.SlotInterval do
  @moduledoc """
  The slot interval field of the meeting type form: whether its custom number
  input is open, the dropdown's options and the hint spelling out what the
  current choice produces.
  """
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Validation.Constraints
  alias TymeslotWeb.CustomInputModeHelper
  alias TymeslotWeb.Themes.Shared.LocalizationHelpers

  # The dropdown value that opens the custom number input. Not a duration, so
  # it can never collide with one: every real value parses as an integer.
  @custom_interval_option "custom"

  # The clock the hint's example times are drawn from. Any hour would do; a
  # round morning start reads as an illustration rather than as real data.
  @hint_start_time ~T[09:00:00]

  @doc "The dropdown value that opens the custom number input."
  @spec custom_option() :: String.t()
  def custom_option, do: @custom_interval_option

  # Whether the custom number input is on screen.
  #
  # Two ways in, and both must be honoured. The organiser can pick "Custom" in
  # the dropdown, which the component records on `:custom_input_mode`. Or the
  # stored value can simply not be one this dropdown offers — written by a
  # seed, an import or a support fix — in which case the input opens on its own
  # so the value stays editable rather than being silently unreachable.
  @spec custom?(map(), term()) :: boolean()
  def custom?(assigns, current_value) do
    chosen? =
      assigns
      |> Map.get(:custom_input_mode, %{})
      |> Map.get(:slot_interval_minutes, false)

    chosen? or off_preset?(parse_interval(current_value))
  end

  defp off_preset?(nil), do: false

  defp off_preset?(interval),
    do: not CustomInputModeHelper.preset_value?(:slot_interval_minutes, interval)

  # `current_value` is whatever is currently stored/selected for this meeting
  # type. It is folded into the option list even when it falls outside the
  # preset table, so a value written by something other than this form (a seed,
  # an import, a support fix) still renders as itself instead of silently
  # falling back to "Same as meeting length" — which the next autosave of any
  # other field would then persist as the value's erasure.
  @spec options(term(), boolean()) :: [{String.t(), String.t()}]
  def options(current_value, custom?) do
    range = Constraints.slot_interval_minutes_range()

    intervals =
      :slot_interval_minutes
      |> CustomInputModeHelper.presets()
      |> Enum.filter(&(&1 in range))
      |> add_stored_interval(parse_interval(current_value), custom?)
      |> Enum.sort()
      |> Enum.map(
        &{dgettext("dashboard_meeting_form", "%{minutes} min", minutes: &1), to_string(&1)}
      )

    [{dgettext("dashboard_meeting_form", "Same as meeting length"), ""}] ++
      intervals ++
      [{dgettext("dashboard_meeting_form", "Custom…"), @custom_interval_option}]
  end

  # While the custom input is open the dropdown reads "Custom…", so folding the
  # stored value in as well would list a value nothing has selected.
  defp add_stored_interval(intervals, _interval, true), do: intervals
  defp add_stored_interval(intervals, nil, _custom?), do: intervals
  defp add_stored_interval(intervals, interval, _custom?), do: Enum.uniq([interval | intervals])

  # Spells out what the current choice produces. An interval is an abstraction
  # until it is three clock times, and five minutes is a very different booking
  # page from sixty; this is where an organiser sees which one they picked.
  @spec hint(term(), term()) :: String.t()
  def hint(interval_value, duration_value) do
    case {parse_interval(interval_value), parse_interval(duration_value)} do
      {nil, nil} ->
        dgettext(
          "dashboard_meeting_form",
          "How far apart booking start times are offered. Leave as default to match the meeting length."
        )

      {nil, duration} ->
        dgettext(
          "dashboard_meeting_form",
          "Matching the meeting length, times will be offered every %{minutes} minutes: %{examples}…",
          minutes: duration,
          examples: interval_examples(duration)
        )

      {interval, _duration} ->
        dgettext(
          "dashboard_meeting_form",
          "Times will be offered every %{minutes} minutes: %{examples}…",
          minutes: interval,
          examples: interval_examples(interval)
        )
    end
  end

  defp interval_examples(minutes) do
    @hint_start_time
    |> Stream.iterate(&Time.add(&1, minutes, :minute))
    |> Enum.take(3)
    |> Enum.map_join(", ", &LocalizationHelpers.format_time_by_locale/1)
  end

  defp parse_interval(value) when is_integer(value), do: value

  defp parse_interval(value) when is_binary(value) do
    case Integer.parse(value) do
      {interval, ""} -> interval
      _invalid -> nil
    end
  end

  defp parse_interval(_value), do: nil
end
