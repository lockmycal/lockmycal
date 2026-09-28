defmodule Tymeslot.Bookings.SubmissionToken do
  @moduledoc """
  Generates booking submission tokens for form rate limiting.
  """

  @spec generate() :: String.t()
  def generate do
    Base.encode64(:crypto.strong_rand_bytes(16))
  end
end
