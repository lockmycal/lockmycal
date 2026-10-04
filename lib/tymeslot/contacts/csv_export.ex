defmodule Tymeslot.Contacts.CsvExport do
  @moduledoc """
  Encodes an organizer's contacts as a CSV file (RFC 4180: comma-separated,
  CRLF line endings, fields quoted when they contain a comma, quote or line
  break).

  The file starts with a UTF-8 byte order mark so Excel reads diacritics
  correctly. Header labels follow the current Gettext locale.

  A cell starting with `=`, `+`, `-`, `@`, a tab or a carriage return is
  prefixed with `'`: a contact's details can come from a public booking form,
  and a spreadsheet would otherwise run such a value as a formula (CSV
  injection).
  """
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Contacts.ContactSchema

  @bom "﻿"
  @formula_triggers ["=", "+", "-", "@", "\t", "\r"]

  @spec encode([ContactSchema.t()]) :: iodata()
  def encode(contacts) do
    [@bom, row(headers()) | Enum.map(contacts, &contact_row/1)]
  end

  defp headers do
    [
      dgettext("dashboard_contacts", "Name"),
      dgettext("dashboard_contacts", "Email"),
      dgettext("dashboard_contacts", "Phone"),
      dgettext("dashboard_contacts", "Company"),
      dgettext("dashboard_contacts", "Note")
    ]
  end

  defp contact_row(%ContactSchema{} = contact) do
    row([contact.name, contact.email, contact.phone, contact.company, contact.note])
  end

  defp row(fields), do: [fields |> Enum.map(&field/1) |> Enum.intersperse(","), "\r\n"]

  defp field(nil), do: ""

  defp field(value) when is_binary(value) do
    value = neutralize_formula(value)

    if String.contains?(value, [",", "\"", "\r", "\n"]),
      do: ["\"", String.replace(value, "\"", "\"\""), "\""],
      else: value
  end

  defp neutralize_formula(value) do
    if String.starts_with?(value, @formula_triggers), do: "'" <> value, else: value
  end
end
