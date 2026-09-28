defmodule Tymeslot.Profiles.Usernames do
  @moduledoc """
  Subcomponent for managing profile usernames.
  Focuses on generation and validation logic.
  """

  alias Tymeslot.Profiles.ProfileQueries

  @type username :: String.t()
  @type user_id :: pos_integer()

  @doc """
  Generates a unique default username for a user.
  """
  @spec generate_default_username(user_id) :: username
  def generate_default_username(user_id) do
    base = "user_#{user_id}"

    if ProfileQueries.username_available?(base) do
      base
    else
      generate_random_username(base, 3)
    end
  end

  @doc """
  Generates a unique, cryptographically random username for a user whose
  custom-URL editing is gated off (`:custom_username_allowed` denied).

  Unlike `generate_default_username/1` (`user_<id>`, meant only as a
  starting point the user remains free to change), this value has to
  last: it's the only link a locked user will ever get, so — unlike
  `user_<id>` — it must not be guessable/enumerable from the user_id,
  otherwise every locked user's booking page could be found by iterating
  small integers. 5 random bytes (40 bits, hex-encoded, e.g.
  `calendar-4f8a2c91d7`) keeps the slug short while making that
  enumeration infeasible; a `username_available?/1` collision at that
  size is astronomically unlikely even at large scale, so the retry loop
  below is a safety net, not the primary uniqueness mechanism.
  """
  @spec generate_locked_username(user_id) :: username
  def generate_locked_username(user_id) do
    generate_random_locked_username(user_id, 3)
  end

  # Private helpers

  defp generate_random_username(base, 0), do: "#{base}_#{random_suffix()}"

  defp generate_random_username(base, attempts) do
    candidate = "#{base}_#{random_suffix()}"

    if ProfileQueries.username_available?(candidate) do
      candidate
    else
      generate_random_username(base, attempts - 1)
    end
  end

  defp random_suffix do
    Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  defp generate_random_locked_username(user_id, 0) do
    # Exhausted retries (astronomically unlikely at 40 bits) — fall back to
    # appending the user_id, which the unique index guarantees is free,
    # same last-resort shape as generate_random_username/2 above.
    "calendar-#{random_locked_token()}-#{user_id}"
  end

  defp generate_random_locked_username(user_id, attempts) do
    candidate = "calendar-#{random_locked_token()}"

    if ProfileQueries.username_available?(candidate) do
      candidate
    else
      generate_random_locked_username(user_id, attempts - 1)
    end
  end

  defp random_locked_token do
    Base.encode16(:crypto.strong_rand_bytes(5), case: :lower)
  end
end
