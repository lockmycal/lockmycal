defmodule Tymeslot.Payments.Validation do
  @moduledoc false

  @spec validate_amount(integer()) :: :ok | {:error, :invalid_amount}
  def validate_amount(amount) when is_integer(amount) do
    limits = Application.get_env(:tymeslot, :payment_amount_limits, [])
    min_cents = Keyword.get(limits, :min_cents, 50)
    max_cents = Keyword.get(limits, :max_cents, 100_000_000)

    cond do
      amount < min_cents -> {:error, :invalid_amount}
      amount > max_cents -> {:error, :invalid_amount}
      true -> :ok
    end
  end

  def validate_amount(_amount), do: {:error, :invalid_amount}
end
