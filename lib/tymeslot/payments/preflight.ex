defmodule Tymeslot.Payments.Preflight do
  @moduledoc false

  alias Tymeslot.Payments.{MetadataSanitizer, Validation}
  alias Tymeslot.Security.RateLimiter

  @spec sanitize_initiation(pos_integer(), pos_integer(), map(), map()) ::
          {:ok, map()} | {:error, term()}
  def sanitize_initiation(amount, user_id, metadata, system_metadata) do
    with :ok <- Validation.validate_amount(amount),
         :ok <- RateLimiter.check_payment_initiation_rate_limit(user_id) do
      MetadataSanitizer.sanitize(metadata, system_metadata)
    end
  end
end
