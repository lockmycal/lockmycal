defmodule TymeslotWeb.Hooks.DashboardInitHook do
  @moduledoc """
  Consolidated hook for dashboard initialization.
  Handles onboarding checks, profile loading, and common dashboard state.
  """
  use Phoenix.VerifiedRoutes,
    endpoint: TymeslotWeb.Endpoint,
    router: TymeslotWeb.Router,
    statics: TymeslotWeb.static_paths()

  import Phoenix.LiveView
  import Phoenix.Component

  require Logger
  alias Tymeslot.CalendarGrid
  alias Tymeslot.Dashboard.DashboardContext
  alias Tymeslot.Dashboard.ExtensionSchema
  alias Tymeslot.Features
  alias Tymeslot.Meetings
  alias Tymeslot.Onboarding
  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.ProfileSchema

  @spec on_mount(:default, map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:cont, Phoenix.LiveView.Socket.t()} | {:halt, Phoenix.LiveView.Socket.t()}
  def on_mount(:default, _params, _session, socket) do
    user = socket.assigns[:current_user]

    cond do
      is_nil(user) ->
        # Let authentication hooks handle missing user
        {:cont, socket}

      !Onboarding.onboarding_completed?(user) ->
        {:halt, redirect(socket, to: ~p"/onboarding")}

      true ->
        mount_dashboard_data(user, socket)
    end
  end

  defp mount_dashboard_data(user, socket) do
    {profile, integration_status, pending_approval_count} =
      load_profile_and_integration_status(user, socket)

    # Read extension/feature config once at mount so components receive stable assigns
    # rather than calling Application.get_env on every render.
    socket =
      socket
      |> assign(:profile, profile)
      |> assign(:integration_status, integration_status)
      # Resolved once here rather than per component: every dashboard surface
      # renders the same clock, and a meeting list must not query per row.
      # AppLocaleHook runs before this one, so the ambient locale is already the
      # organiser's when it supplies the preset.
      |> assign(
        :time_format,
        CalendarGrid.get_user_time_format(user.id, Gettext.get_locale(TymeslotWeb.Gettext))
      )
      |> assign(:pending_approval_count, pending_approval_count)
      |> assign(:payments_allowed, payments_allowed?(user.id))
      |> assign_new(:saving, fn -> false end)
      |> assign_new(:saving_timer_ref, fn -> nil end)
      |> assign(
        :sidebar_extensions,
        :tymeslot
        |> Application.get_env(:dashboard_sidebar_extensions, [])
        |> ExtensionSchema.filter_valid()
      )
      |> assign(
        :feature_placeholder_components,
        Application.get_env(:tymeslot, :feature_placeholder_components, %{})
      )
      |> assign(
        :dashboard_action_components,
        Application.get_env(:tymeslot, :dashboard_action_components, %{})
      )
      |> assign(
        :dashboard_feature_gates,
        Application.get_env(:tymeslot, :dashboard_feature_gates, %{})
      )

    {:cont, socket}
  end

  # The static render is thrown away the moment the socket connects, but
  # several dashboard surfaces (onboarding checklist, theme lock overlay,
  # calendar-connect banner) branch on `integration_status` in that first
  # paint too, so it must be the real value there, not the all-false
  # default — otherwise a fully set-up host sees a false "setup incomplete"
  # flash before the socket connects. `DashboardContext.get_integration_status/1`
  # is cache-backed (5 minutes), so fetching it synchronously here is cheap.
  # `pending_approval_count` has no such first-paint dependency (it only
  # feeds a sidebar notification badge), so it stays 0 until the connected
  # render fills in the real count.
  defp load_profile_and_integration_status(user, socket) do
    if connected?(socket) do
      fetch_profile_and_integration_status(user)
    else
      {profile_or_placeholder(user), DashboardContext.get_integration_status(user.id), 0}
    end
  end

  # Unwraps a `Task.yield_many/2` result at `index`, falling back to `default`
  # when the task timed out, crashed, or was never present.
  defp task_result(results, index, default) do
    case Enum.at(results, index) do
      {_task, {:ok, value}} -> value
      _timeout_or_error -> default
    end
  end

  defp fetch_profile_and_integration_status(user) do
    # Load profile, integration status, and the pending-approval count
    # concurrently — all three are independent.
    profile_task =
      Task.Supervisor.async_nolink(Tymeslot.TaskSupervisor, fn ->
        profile_or_placeholder(user)
      end)

    integration_task =
      Task.Supervisor.async_nolink(Tymeslot.TaskSupervisor, fn ->
        DashboardContext.get_integration_status(user.id)
      end)

    pending_approval_task =
      Task.Supervisor.async_nolink(Tymeslot.TaskSupervisor, fn ->
        Meetings.count_awaiting_approval_for_organizer(user.id)
      end)

    results =
      Task.yield_many([profile_task, integration_task, pending_approval_task], :timer.seconds(5))

    Enum.each(results, fn
      {task, nil} -> Task.shutdown(task, :brutal_kill)
      _result -> :ok
    end)

    profile = task_result(results, 0, %ProfileSchema{user_id: user.id})
    integration_status = task_result(results, 1, DashboardContext.default_integration_status())
    pending_approval_count = task_result(results, 2, 0)

    {profile, integration_status, pending_approval_count}
  end

  # An account can predate atomic registration and have no profile row. It is
  # created here rather than stood in for by an unsaved struct, which every
  # settings form would then fail to update.
  defp profile_or_placeholder(user) do
    case Profiles.get_or_create_profile(user.id) do
      {:ok, profile} ->
        profile

      {:error, reason} ->
        Logger.error("Could not create missing profile for dashboard",
          user_id: user.id,
          reason: inspect(reason)
        )

        %ProfileSchema{user_id: user.id}
    end
  end

  # Whether the host can reach the payments dashboard unlocked. Mirrors the
  # gate in `PaymentsHandlers`: both `:ok` and `{:error, :stripe_required}`
  # mean the feature is allowed (Stripe just isn't connected yet). Any other
  # result — including an unrecognised error atom or a SaaS checker crash
  # (`Features.check_access/2` turns those into
  # `{:error, :feature_access_checker_failed}`) — fails closed to `false`.
  # Deliberately just this one flag: an earlier revision also split off a
  # `payments_feature_enabled` assign (a coarser "does the feature exist at
  # all" check for a standalone sidebar link this fork briefly reintroduced),
  # but its catch-all treated any non-`:feature_disabled` result — including
  # a checker crash — as "enabled", the opposite of fail-closed. That link
  # doesn't exist in this tree (Payments lives inside the Integrations hub's
  # own tab, see README_MERGE.md), so the flag was dropped rather than fixed;
  # if the hub's tab ever needs the same "on at all" distinction, read
  # `Tymeslot.MeetingPayments.enabled?/0` directly (a plain operator-flag
  # lookup, immune to checker-response ambiguity), the same pattern
  # `Tymeslot.Analytics.enabled?/0` already uses for its own sidebar item.
  defp payments_allowed?(user_id) do
    case Features.check_access(user_id, :meeting_payments) do
      :ok -> true
      {:error, :stripe_required} -> true
      _other -> false
    end
  end
end
