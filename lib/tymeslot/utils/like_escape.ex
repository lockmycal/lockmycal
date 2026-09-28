defmodule Tymeslot.Utils.LikeEscape do
  @moduledoc """
  Escapes PostgreSQL `LIKE`/`ILIKE` wildcard metacharacters (`%`, `_`, and
  the escape character `\\` itself) so a user-typed search term is matched
  literally rather than as a pattern.

  Shared by every case-insensitive substring search built on `ilike/2`
  (`Tymeslot.Auth.AdminUserQueries.list_all_users/1`,
  `Tymeslot.Contacts.ContactQueries.list_contacts/2`,
  `Tymeslot.Integrations.Calendar.ProviderCalendarEventQueries.search/3`) —
  each wraps the escaped term in its own `"%" <> escape(term) <> "%"`
  pattern, since the surrounding query (fields searched, extra `where`
  clauses) differs per call site.
  """

  @doc """
  Escapes `\\`, `%`, and `_` in `term` by prefixing each with a backslash,
  so it can be embedded in an `ilike/2` pattern without those characters
  being interpreted as wildcards.
  """
  @spec escape(String.t()) :: String.t()
  def escape(term) when is_binary(term) do
    String.replace(term, ~r/[\\%_]/, "\\\\\\0")
  end
end
