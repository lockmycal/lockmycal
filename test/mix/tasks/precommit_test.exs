defmodule Mix.Tasks.PrecommitTest do
  use ExUnit.Case, async: true

  @moduletag :dev_support

  alias Mix.Tasks.Precommit

  @steps [
    {"credo", ~w[credo --strict], :dev},
    {"js", ~w[test.js], :dev},
    {"dialyzer", ~w[dialyzer.incremental], :dev}
  ]

  describe "applicable/2" do
    test "keeps every step when the project has JavaScript tests" do
      assert {@steps, []} = Precommit.applicable(@steps, true)
    end

    test "drops the JavaScript step, and says why, when the project has none" do
      assert {[{"credo", _args, _env}, {"dialyzer", _more, _env2}], [{"js", reason}]} =
               Precommit.applicable(@steps, false)

      assert reason =~ "no assets/js"
    end

    test "has nothing to drop when the gate has no JavaScript step" do
      steps = Enum.reject(@steps, &match?({"js", _args, _env}, &1))

      assert {^steps, []} = Precommit.applicable(steps, false)
    end
  end
end
