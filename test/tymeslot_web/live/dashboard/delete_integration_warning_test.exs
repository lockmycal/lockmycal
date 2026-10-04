defmodule TymeslotWeb.Dashboard.DeleteIntegrationWarningTest do
  @moduledoc """
  The remove-integration dialog shows the configured
  `Tymeslot.Integrations.Calendar.IntegrationDeletionHook`'s warning for an
  integration whose deletion removes more than the integration itself.
  """

  # Not async: toggles global app env (the configured hook).
  use TymeslotWeb.LiveCase, async: false

  @moduletag :integrations
  @moduletag :live

  import Tymeslot.DashboardTestHelpers
  import Tymeslot.Factory

  defmodule WarningHook do
    @moduledoc false
    @behaviour Tymeslot.Integrations.Calendar.IntegrationDeletionHook

    @impl Tymeslot.Integrations.Calendar.IntegrationDeletionHook
    def on_integration_deleted(_integration), do: :ok

    @impl Tymeslot.Integrations.Calendar.IntegrationDeletionHook
    def deletion_warning(%{base_url: "https://hosted.example.com/dav"}),
      do: "All events in this calendar are deleted too."

    def deletion_warning(_integration), do: nil
  end

  defmodule SilentHook do
    @moduledoc false
    @behaviour Tymeslot.Integrations.Calendar.IntegrationDeletionHook

    @impl Tymeslot.Integrations.Calendar.IntegrationDeletionHook
    def on_integration_deleted(_integration), do: :ok
  end

  setup :setup_dashboard_user

  setup do
    previous = Application.fetch_env(:tymeslot, :calendar_integration_deletion_hook)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:tymeslot, :calendar_integration_deletion_hook, value)
        :error -> Application.delete_env(:tymeslot, :calendar_integration_deletion_hook)
      end
    end)
  end

  test "shows the hook's warning for the integration it applies to", %{conn: conn, user: user} do
    Application.put_env(:tymeslot, :calendar_integration_deletion_hook, WarningHook)
    hosted = insert(:calendar_integration, user: user, base_url: "https://hosted.example.com/dav")

    view = open_dialog(conn, hosted.id)

    assert view |> element("#delete-calendar-modal-deletion-warning") |> render() =~
             "All events in this calendar are deleted too."
  end

  test "shows no warning for other integrations", %{conn: conn, user: user} do
    Application.put_env(:tymeslot, :calendar_integration_deletion_hook, WarningHook)
    other = insert(:calendar_integration, user: user, base_url: "https://dav.example.com")

    view = open_dialog(conn, other.id)

    refute has_element?(view, "#delete-calendar-modal-deletion-warning")
  end

  test "shows no warning for a hook without deletion_warning/1", %{conn: conn, user: user} do
    Application.put_env(:tymeslot, :calendar_integration_deletion_hook, SilentHook)
    hosted = insert(:calendar_integration, user: user, base_url: "https://hosted.example.com/dav")

    view = open_dialog(conn, hosted.id)

    refute has_element?(view, "#delete-calendar-modal-deletion-warning")
  end

  defp open_dialog(conn, integration_id) do
    {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")

    view
    |> with_target("#delete-calendar-modal")
    |> render_click("show", %{"id" => to_string(integration_id)})

    view
  end
end
