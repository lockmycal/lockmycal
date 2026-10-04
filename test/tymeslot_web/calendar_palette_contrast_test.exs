defmodule TymeslotWeb.CalendarPaletteContrastTest do
  @moduledoc """
  The calendar colours (`--color-calendar-*`) paint event chips with white text
  on the dashboard grid and the public calendar, so each one must keep that
  text readable: at least 4.5:1 against white (WCAG AA). They are defined in
  three stylesheets that have to agree, since the dashboard and the booking
  theme build them separately.
  """

  use ExUnit.Case, async: true

  @moduletag :ui

  alias Tymeslot.Utils.Colour

  @stylesheets [
    "assets/css/app.css",
    "assets/css/base/variables.css",
    "assets/css/scheduling/themes/quill/modules/variables.css"
  ]

  defp palette(path) do
    ~r/--color-calendar-([a-z0-9]+):\s*(#[0-9a-fA-F]{6})/
    |> Regex.scan(File.read!(path))
    |> Map.new(fn [_match, name, hex] -> {name, Colour.normalise_hex(hex)} end)
  end

  test "every stylesheet defines the same calendar colours, all at WCAG AA with white text" do
    [reference | _others] = palettes = Enum.map(@stylesheets, &palette/1)
    assert map_size(reference) > 0

    for {path, colours} <- Enum.zip(@stylesheets, palettes) do
      assert colours == reference, "#{path} is out of sync with app.css"

      for {name, hex} <- colours do
        ratio = Colour.contrast_ratio(hex, "#ffffff")

        assert ratio >= 4.5,
               "#{path}: --color-calendar-#{name} (#{hex}) gives white text only " <>
                 "#{Float.round(ratio, 2)}:1"
      end
    end
  end
end
