defmodule Tymeslot.I18n.ResolveTest do
  use ExUnit.Case, async: true

  @moduletag :i18n
  @moduletag :unit

  alias Tymeslot.I18n.Resolve

  defp row(locale, fields), do: Map.merge(%{locale: locale}, fields)

  describe "text/4" do
    test "returns the fallback when there is no matching locale row" do
      translations = [row("de", %{name: "Kurzes Gespräch"})]

      assert Resolve.text(translations, "fr", :name, "Quick Chat") == "Quick Chat"
    end

    test "returns the translated value for a matching locale" do
      translations = [row("de", %{name: "Kurzes Gespräch"})]

      assert Resolve.text(translations, "de", :name, "Quick Chat") == "Kurzes Gespräch"
    end

    test "falls back per-field when the matching row's field is nil" do
      translations = [row("de", %{name: "Kurzes Gespräch", description: nil})]

      assert Resolve.text(translations, "de", :description, "base description") ==
               "base description"
    end

    test "falls back per-field when the matching row's field is blank" do
      translations = [row("de", %{name: ""})]

      assert Resolve.text(translations, "de", :name, "Quick Chat") == "Quick Chat"
    end

    test "returns the fallback when translations is nil" do
      assert Resolve.text(nil, "de", :name, "Quick Chat") == "Quick Chat"
    end

    test "returns the fallback when translations is an empty list" do
      assert Resolve.text([], "de", :name, "Quick Chat") == "Quick Chat"
    end

    test "picks the row matching the requested locale among several" do
      translations = [
        row("de", %{name: "Kurzes Gespräch"}),
        row("fr", %{name: "Discussion rapide"})
      ]

      assert Resolve.text(translations, "fr", :name, "Quick Chat") == "Discussion rapide"
    end
  end
end
