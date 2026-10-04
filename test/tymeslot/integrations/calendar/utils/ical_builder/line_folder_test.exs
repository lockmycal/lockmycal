defmodule Tymeslot.Integrations.Calendar.ICalBuilder.LineFolderTest do
  use ExUnit.Case, async: true

  @moduletag :calendar
  @moduletag :unit

  alias Tymeslot.Integrations.Calendar.ICalBuilder.LineFolder

  defp octets(folded), do: folded |> String.split("\r\n") |> Enum.map(&byte_size/1)

  describe "fold_lines/1" do
    test "never tears a multi-byte character, whatever byte the limit falls on" do
      # Shifting the text one byte at a time puts the 75-octet limit on every
      # byte of every two-byte character in turn, the lead byte included.
      for pad <- 0..4 do
        line = "DESCRIPTION:" <> String.duplicate("x", pad) <> String.duplicate("řěšč", 30)
        folded = LineFolder.fold_lines(line)

        assert String.valid?(folded)
        assert Enum.all?(String.split(folded, "\r\n"), &String.valid?/1)
        assert LineFolder.unfold_lines(folded) == [line]
      end
    end

    test "keeps every line within 75 octets" do
      line = "SUMMARY:" <> String.duplicate("Příliš žluťoučký kůň ", 10)

      assert line |> LineFolder.fold_lines() |> octets() |> Enum.all?(&(&1 <= 75))
    end

    test "cuts an ASCII line at exactly 75 octets" do
      line = String.duplicate("a", 160)

      assert line |> LineFolder.fold_lines() |> octets() == [75, 75, 12]
    end

    test "leaves a short line alone" do
      assert LineFolder.fold_lines("SUMMARY:Krátká schůzka") == "SUMMARY:Krátká schůzka"
    end
  end
end
