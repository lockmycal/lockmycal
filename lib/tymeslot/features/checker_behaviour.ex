defmodule Tymeslot.Features.CheckerBehaviour do
  @moduledoc """
  Behaviour contract for feature access checker implementations.

  Core provides `Tymeslot.Features.DefaultAccessChecker` which always
  returns `:ok`. SaaS overrides the configured checker to gate features
  behind subscription tiers.
  """

  @callback check_access(user_id :: integer(), feature :: atom()) ::
              :ok
              | {:error,
                 :insufficient_plan | :feature_disabled | :pro_required | :stripe_required}

  @doc """
  The maximum number of `resource` (e.g. `:calendar_integrations`) the user
  may own, or `:unlimited`. Optional: a checker that doesn't implement it
  imposes no limit, see `Tymeslot.Features.limit/2`.
  """
  @callback limit(user_id :: integer(), resource :: atom()) :: non_neg_integer() | :unlimited

  @optional_callbacks limit: 2
end
