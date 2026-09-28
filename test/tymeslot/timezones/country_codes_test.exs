defmodule Tymeslot.Timezones.CountryCodesTest do
  use ExUnit.Case, async: true

  @moduletag :utils

  alias Tymeslot.Timezones.CountryCodes

  describe "name_for/1" do
    test "returns the common name for a known code" do
      assert CountryCodes.name_for("CZ") == "Czechia"
      assert CountryCodes.name_for("US") == "United States"
    end

    test "every alpha2 code has a real name, not a bare fallback to the code itself" do
      for code <- CountryCodes.alpha2_codes() do
        name = CountryCodes.name_for(code)
        assert name != code, "#{code} is missing from the country name map"
      end
    end

    test "falls back to the code itself for an unrecognised input" do
      assert CountryCodes.name_for("ZZ") == "ZZ"
      assert CountryCodes.name_for(:not_a_string) == "not_a_string"
    end
  end
end
