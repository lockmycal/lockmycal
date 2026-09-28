defmodule Tymeslot.Payments.Behaviours.PubSubProvider do
  @moduledoc """
  Behaviour for PubSub operations.
  This allows us to mock PubSub calls during testing.
  """

  @callback broadcast(topic :: String.t(), message :: any()) ::
              :ok | {:error, term()}
end
