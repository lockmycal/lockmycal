defmodule Tymeslot.Payments.Subscriptions do
  @moduledoc false

  require Logger

  alias Tymeslot.Payments.Config

  @spec cancel_subscription(String.t(), pos_integer(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def cancel_subscription(subscription_id, user_id, opts \\ []) do
    manager = subscription_manager()

    if manager do
      manager.cancel_subscription(subscription_id, user_id, opts)
    else
      Logger.error("Subscription manager not configured")
      {:error, :subscriptions_not_supported}
    end
  end

  @spec update_subscription(String.t(), String.t(), pos_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def update_subscription(
        subscription_id,
        new_stripe_price_id,
        user_id,
        metadata \\ %{}
      ) do
    manager = subscription_manager()

    if manager do
      manager.update_subscription(
        subscription_id,
        new_stripe_price_id,
        user_id,
        metadata
      )
    else
      Logger.error("Subscription manager not configured")
      {:error, :subscriptions_not_supported}
    end
  end

  @spec downgrade_subscription(String.t(), String.t(), pos_integer(), map()) ::
          {:ok, map()} | {:error, term()}
  def downgrade_subscription(
        subscription_id,
        new_stripe_price_id,
        user_id,
        metadata \\ %{}
      ) do
    manager = subscription_manager()

    if manager && function_exported?(manager, :downgrade_subscription, 4) do
      manager.downgrade_subscription(
        subscription_id,
        new_stripe_price_id,
        user_id,
        metadata
      )
    else
      Logger.error("Subscription manager not configured or doesn't support downgrades")
      {:error, :downgrades_not_supported}
    end
  end

  defp subscription_manager do
    Config.subscription_manager()
  end
end
