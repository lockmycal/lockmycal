defmodule Tymeslot.Utils.LikeEscapeTest do
  use ExUnit.Case, async: true

  @moduletag :utils

  alias Tymeslot.Utils.LikeEscape

  describe "escape/1" do
    test "leaves a term with no metacharacters unchanged" do
      assert LikeEscape.escape("plain term") == "plain term"
    end

    test "escapes %, _, and \\ with a leading backslash" do
      assert LikeEscape.escape("50%_off") == "50\\%\\_off"
      assert LikeEscape.escape("a\\b") == "a\\\\b"
    end

    test "escaping is idempotent-safe: the escaped output round-trips through Regex.escape-style expectations" do
      escaped = LikeEscape.escape("100%_done\\now")
      assert escaped == "100\\%\\_done\\\\now"
    end
  end
end
