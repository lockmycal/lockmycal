defmodule Tymeslot.Contacts.CsvExportTest do
  use ExUnit.Case, async: true

  @moduletag :contacts

  alias Tymeslot.Contacts.ContactSchema
  alias Tymeslot.Contacts.CsvExport

  defp encode(contacts), do: contacts |> CsvExport.encode() |> IO.iodata_to_binary()

  defp contact(attrs), do: struct(%ContactSchema{name: "Jane", email: "jane@example.com"}, attrs)

  test "starts with a UTF-8 BOM and a header row, one CRLF-terminated row per contact" do
    csv =
      encode([
        contact(name: "Jana Nováková", phone: "+420 123", company: "Acme", note: "Ráno"),
        contact(name: "Bob", email: "bob@example.com")
      ])

    assert csv ==
             "﻿Name,Email,Phone,Company,Note\r\n" <>
               "Jana Nováková,jane@example.com,'+420 123,Acme,Ráno\r\n" <>
               "Bob,bob@example.com,,,\r\n"
  end

  test "an empty list is just the header row" do
    assert encode([]) == "﻿Name,Email,Phone,Company,Note\r\n"
  end

  test "quotes fields holding a comma, a quote or a line break" do
    csv = encode([contact(company: "Acme, s.r.o.", note: "Said \"hi\"\nand left")])

    assert csv =~ ~s|,"Acme, s.r.o.","Said ""hi""\nand left"\r\n|
  end

  test "neutralises values a spreadsheet would run as a formula" do
    csv =
      encode([
        contact(name: "=HYPERLINK(\"http://evil\")", company: "@SUM(A1)", note: "-1+1")
      ])

    assert csv =~ ~s|"'=HYPERLINK(""http://evil"")",|
    assert csv =~ ",'@SUM(A1),'-1+1\r\n"
  end
end
