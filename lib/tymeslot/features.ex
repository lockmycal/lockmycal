defmodule Tymeslot.Features do
  @moduledoc """
  Feature access checks for paid and gated functionality.

  Core uses a configurable checker module. SaaS can override this via config.
  """

  require Logger

  alias Tymeslot.Infrastructure.ErrorTracking
  alias Tymeslot.Infrastructure.Logging.LogFormat

  @type access_error ::
          :insufficient_plan
          | :feature_disabled
          | :pro_required
          | :stripe_required
          | :feature_access_checker_failed

  @spec check_access(integer(), atom()) :: :ok | {:error, access_error()}
  def check_access(user_id, feature) when is_integer(user_id) and is_atom(feature) do
    module = checker_module()

    # Use configured checker (e.g., SaaS subscription checker)
    try do
      case module.check_access(user_id, feature) do
        :ok ->
          :ok

        {:error, :insufficient_plan} = error ->
          error

        {:error, :feature_disabled} = error ->
          error

        {:error, :pro_required} = error ->
          error

        {:error, :stripe_required} = error ->
          error

        {:error, reason} ->
          Logger.warning("Feature access checker returned error",
            user_id: user_id,
            feature: feature,
            reason: LogFormat.reason(reason)
          )

          {:error, :feature_access_checker_failed}

        other ->
          Logger.warning("Feature access checker returned unexpected value",
            user_id: user_id,
            feature: feature,
            result: LogFormat.reason(other)
          )

          {:error, :feature_access_checker_failed}
      end
    rescue
      exception ->
        ErrorTracking.report_error(exception, __STACKTRACE__, %{
          user_id: user_id,
          feature: feature
        })

        {:error, :feature_access_checker_failed}
    end
  end

  def check_access(user_id, feature) do
    Logger.warning("Feature access check received invalid inputs",
      user_id: user_id,
      feature: feature
    )

    {:error, :feature_access_checker_failed}
  end

  @doc """
  The maximum number of `resource` the user may own, as decided by the
  configured checker's optional `limit/2` callback, or `:unlimited` when it
  doesn't implement one (Core's own default).

  Fails open: a checker that raises or answers something other than a
  non-negative integer or `:unlimited` is logged and treated as no limit, so
  a broken overlay can't stop anyone connecting what they already could.
  """
  @spec limit(integer(), atom()) :: non_neg_integer() | :unlimited
  def limit(user_id, resource) when is_integer(user_id) and is_atom(resource) do
    module = checker_module()
    Code.ensure_loaded(module)

    if function_exported?(module, :limit, 2) do
      try do
        case module.limit(user_id, resource) do
          :unlimited ->
            :unlimited

          max when is_integer(max) and max >= 0 ->
            max

          other ->
            Logger.error("Feature limit checker returned unexpected value",
              user_id: user_id,
              resource: resource,
              result: LogFormat.reason(other)
            )

            :unlimited
        end
      rescue
        exception ->
          Logger.error("Feature limit checker raised",
            user_id: user_id,
            resource: resource,
            exception: exception,
            kind: :error,
            stacktrace: __STACKTRACE__
          )

          :unlimited
      end
    else
      :unlimited
    end
  end

  @doc """
  Whether the user, currently owning `current_count` of `resource`, may add
  one more.
  """
  @spec check_limit(integer(), atom(), non_neg_integer()) :: :ok | {:error, :limit_reached}
  def check_limit(user_id, resource, current_count) when is_integer(current_count) do
    case limit(user_id, resource) do
      :unlimited -> :ok
      max when current_count < max -> :ok
      _max -> {:error, :limit_reached}
    end
  end

  defp checker_module do
    Application.get_env(
      :tymeslot,
      :feature_access_checker,
      Tymeslot.Features.DefaultAccessChecker
    )
  end

  @doc """
  Whether the host may see and configure meeting payments.

  `{:error, :stripe_required}` counts as allowed: the plan includes the feature
  and the host simply has not connected a charges-enabled Stripe account yet,
  so the settings must stay reachable for them to connect one. Whether a price
  may actually be *persisted* without a live account is a separate question,
  answered by the meeting-type changeset.

  Four call sites — the dashboard init hook, the integrations hub, the payments
  controller and the meeting-type form — each carried their own copy of this
  decision and cited three different, mutually inconsistent authorities for it,
  one of which holds no gate at all. This is the authority.
  """
  @spec meeting_payments_allowed?(integer()) :: boolean()
  def meeting_payments_allowed?(user_id) do
    case check_access(user_id, :meeting_payments) do
      :ok -> true
      {:error, :stripe_required} -> true
      _denied -> false
    end
  end
end
