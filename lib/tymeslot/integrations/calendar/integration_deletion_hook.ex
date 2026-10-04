defmodule Tymeslot.Integrations.Calendar.IntegrationDeletionHook do
  @moduledoc """
  Optional hook invoked after a user deletes one of their calendar
  integrations from the dashboard, letting an external layer (e.g. an overlay
  that hosts calendars itself) tear down what it created alongside the
  integration.

  Configured via `config :tymeslot, :calendar_integration_deletion_hook, MyHook`.
  Core keeps a safe `nil` default and behaves identically whether or not a hook
  is set.

  Runs once the deletion has been committed, in the caller's process (for the
  dashboard, the LiveView), so it can't abort or undo it: the hook handles and
  retries its own failures. It is called for every deleted integration and
  must ignore the ones it didn't create. Deleting the whole account doesn't go
  through it — that is `Tymeslot.Auth.Behaviours.AccountDeletionHook`.

  A hook that removes more than the integration itself should also say so
  up front: the optional `deletion_warning/1` returns a translated sentence
  the delete confirmation dialog shows for that integration.
  """

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema

  @callback on_integration_deleted(integration :: CalendarIntegrationSchema.t()) :: :ok

  @doc "What else deleting `integration` removes, for the confirmation dialog; `nil` for nothing."
  @callback deletion_warning(integration :: CalendarIntegrationSchema.t()) :: String.t() | nil

  @optional_callbacks deletion_warning: 1

  @doc "Runs the configured hook, if any, for a just-deleted integration."
  @spec run(CalendarIntegrationSchema.t()) :: :ok
  def run(integration) do
    case Application.get_env(:tymeslot, :calendar_integration_deletion_hook) do
      nil -> :ok
      hook -> hook.on_integration_deleted(integration)
    end
  end

  @doc "The configured hook's warning for deleting `integration`, or `nil`."
  @spec warning(CalendarIntegrationSchema.t()) :: String.t() | nil
  def warning(integration) do
    hook = Application.get_env(:tymeslot, :calendar_integration_deletion_hook)

    if hook && Code.ensure_loaded?(hook) && function_exported?(hook, :deletion_warning, 1) do
      hook.deletion_warning(integration)
    end
  end
end
