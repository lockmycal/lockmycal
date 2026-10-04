defmodule Tymeslot.Integrations.Calendar.IntegrationDeletionHookTest do
  # Not async: toggles global app env (the configured hook).
  use Tymeslot.DataCase, async: false

  @moduletag :integrations

  import Tymeslot.Factory
  alias Tymeslot.Integrations.Calendar.Deletion

  defmodule NotifyingHook do
    @moduledoc false
    @behaviour Tymeslot.Integrations.Calendar.IntegrationDeletionHook

    @impl Tymeslot.Integrations.Calendar.IntegrationDeletionHook
    def on_integration_deleted(integration) do
      send(self(), {:integration_deleted, integration.id, integration.base_url})
      :ok
    end
  end

  setup do
    previous = Application.fetch_env(:tymeslot, :calendar_integration_deletion_hook)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:tymeslot, :calendar_integration_deletion_hook, value)
        :error -> Application.delete_env(:tymeslot, :calendar_integration_deletion_hook)
      end
    end)

    user = insert(:user)
    insert(:profile, user: user)

    %{user: user}
  end

  test "runs the configured hook with the deleted integration", %{user: user} do
    Application.put_env(:tymeslot, :calendar_integration_deletion_hook, NotifyingHook)
    integration = insert(:calendar_integration, user: user, base_url: "https://dav.example.com")

    assert {:ok, _result} = Deletion.delete_with_primary_reassignment(user.id, integration.id)

    assert_received {:integration_deleted, id, "https://dav.example.com"}
    assert id == integration.id
  end

  test "doesn't run the hook when nothing was deleted", %{user: user} do
    Application.put_env(:tymeslot, :calendar_integration_deletion_hook, NotifyingHook)
    other_user = insert(:user)
    integration = insert(:calendar_integration, user: other_user)

    assert {:error, :not_found} =
             Deletion.delete_with_primary_reassignment(user.id, integration.id)

    refute_received {:integration_deleted, _id, _base_url}
  end

  test "deletes normally without a hook configured", %{user: user} do
    Application.put_env(:tymeslot, :calendar_integration_deletion_hook, nil)
    integration = insert(:calendar_integration, user: user)

    assert {:ok, _result} = Deletion.delete_with_primary_reassignment(user.id, integration.id)
  end
end
