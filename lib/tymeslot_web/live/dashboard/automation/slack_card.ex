defmodule TymeslotWeb.Dashboard.Automation.SlackCard do
  @moduledoc false
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Slack.SlackIntegrationSchema
  alias TymeslotWeb.Components.Icons.IconComponents
  alias TymeslotWeb.Components.UI.StatusSwitch
  alias TymeslotWeb.Dashboard.Automation.Helpers, as: AutomationHelpers

  attr :integration, :map, required: true
  attr :time_format, :string, required: true
  attr :testing, :boolean, default: false
  attr :target, :any, required: true
  attr :on_edit, :any, required: true
  attr :on_delete, :any, required: true
  attr :on_toggle, :string, required: true
  attr :on_test, :any, required: true
  attr :on_view_deliveries, :any, required: true
  attr :on_reenable, :any, default: nil
  attr :on_pick_channel, :any, default: nil
  attr :on_disconnect, :any, default: nil
  attr :on_reconnect, :any, default: nil

  @spec slack_card(map()) :: Phoenix.LiveView.Rendered.t()
  def slack_card(assigns) do
    assigns = assign(assigns, :status, SlackIntegrationSchema.status(assigns.integration))

    ~H"""
    <div class={[
      "card-glass p-4",
      if(@status == :active, do: "card-glass-available", else: "card-glass-unavailable")
    ]}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
        <div class="flex min-w-0 flex-1 items-center gap-4">
          <IconComponents.icon
            name={:slack}
            class="w-5 h-5 text-neutral-600 dark:text-neutral-300 shrink-0"
          />

          <div class="min-w-0 flex-1">
            <h3 class="truncate text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
              {@integration.name}
            </h3>
            <p class="mt-0.5 truncate text-token-sm text-neutral-500">
              {location_label(@integration)}
            </p>
            <div class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-token-xs text-neutral-500">
              <%= if @status == :pending_oauth do %>
                <span class="text-amber-600 font-medium">
                  {dgettext("dashboard_automation_chat", "Pick a channel to finish setup.")}
                </span>
              <% else %>
                <span :for={event <- @integration.events} class="inline-flex items-center gap-1">
                  <div class={[
                    "w-1.5 h-1.5 rounded-full",
                    if(@status == :active, do: "bg-primary-500", else: "bg-neutral-300")
                  ]} />
                  {event}
                </span>
                <span class="inline-flex items-center gap-1 text-neutral-400">
                  <.icon name="hero-clock" class="w-3.5 h-3.5" />
                  {last_triggered_label(@integration, @time_format)}
                </span>
                <span :if={@status == :auto_disabled} class="text-red-600 font-medium">
                  {dgettext("dashboard_automation_chat", "Disabled: %{reason}",
                    reason: disabled_reason_label(@integration.disabled_reason)
                  )}
                </span>
              <% end %>
            </div>
          </div>

          <.status_badge status={@status} />
        </div>

        <div class="flex flex-wrap items-center gap-2 sm:justify-end">
          <StatusSwitch.status_switch
            :if={@status in [:active, :paused]}
            id={"slack-toggle-#{@integration.id}"}
            checked={@integration.is_active}
            on_change={@on_toggle}
            target={@target}
            phx_value_id={"#{@integration.id}"}
            size={:small}
            show_icon={false}
          />

          <button
            :if={@status == :pending_oauth && @on_pick_channel}
            phx-click={@on_pick_channel}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Pick a channel")}
            aria-label={dgettext("dashboard_automation_chat", "Pick a channel")}
          >
            <.icon name="hero-hashtag" class="w-5 h-5" />
          </button>

          <button
            :if={@status == :pending_oauth && @integration.app_mode == "oauth" && @on_reconnect}
            phx-click={@on_reconnect}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Reconnect")}
            aria-label={dgettext("dashboard_automation_chat", "Reconnect")}
          >
            <.icon name="hero-arrow-path" class="w-5 h-5" />
          </button>

          <button
            :if={@status == :auto_disabled && @on_reenable}
            phx-click={@on_reenable}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Re-enable")}
            aria-label={dgettext("dashboard_automation_chat", "Re-enable")}
          >
            <.icon name="hero-arrow-path" class="w-5 h-5" />
          </button>

          <button
            :if={@status in [:active, :paused]}
            phx-click={@on_test}
            disabled={@testing || @status != :active}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={test_button_title(@status, @testing)}
            aria-label={test_button_title(@status, @testing)}
          >
            <%= if @testing do %>
              <.icon name="hero-arrow-path" class="w-5 h-5 animate-spin" />
            <% else %>
              <.icon name="hero-bolt" class="w-5 h-5" />
            <% end %>
          </button>

          <button
            :if={@status != :pending_oauth}
            phx-click={@on_view_deliveries}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "View delivery logs")}
            aria-label={dgettext("dashboard_automation_chat", "View delivery logs")}
          >
            <.icon name="hero-document-text" class="w-5 h-5" />
          </button>

          <button
            :if={@status != :pending_oauth}
            phx-click={@on_edit}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Edit")}
            aria-label={dgettext("dashboard_automation_chat", "Edit")}
          >
            <.icon name="hero-pencil-square" class="w-5 h-5" />
          </button>

          <button
            :if={@on_disconnect && @integration.app_mode == "oauth" && @integration.channel_id}
            phx-click={@on_disconnect}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Disconnect Slack")}
            aria-label={dgettext("dashboard_automation_chat", "Disconnect Slack")}
          >
            <.icon name="hero-link-slash" class="w-5 h-5" />
          </button>

          <button
            phx-click={@on_delete}
            class="row-action-button row-action-button--danger"
            title={dgettext("dashboard_automation_chat", "Delete")}
            aria-label={dgettext("dashboard_automation_chat", "Delete")}
          >
            <.icon name="hero-trash" class="w-5 h-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp status_badge(%{status: :pending_oauth} = assigns) do
    ~H"""
    <span class="shrink-0 inline-flex items-center gap-1.5 rounded-token-full px-2.5 py-1 text-token-xs font-semibold bg-amber-50 border border-amber-200 text-amber-700">
      <span class="h-1.5 w-1.5 rounded-token-full bg-amber-500 animate-pulse" aria-hidden="true"></span>
      {dgettext("dashboard_automation_chat", "Channel needed")}
    </span>
    """
  end

  defp status_badge(%{status: :active} = assigns) do
    ~H"""
    <span class="shrink-0 inline-flex items-center gap-1.5 rounded-token-full px-2.5 py-1 text-token-xs font-semibold bg-emerald-50 border border-emerald-200 text-emerald-700">
      <span class="h-1.5 w-1.5 rounded-token-full bg-emerald-500" aria-hidden="true"></span>
      {dgettext("dashboard_automation_chat", "Active")}
    </span>
    """
  end

  defp status_badge(%{status: :paused} = assigns) do
    ~H"""
    <span class="shrink-0 inline-flex items-center gap-1.5 rounded-token-full px-2.5 py-1 text-token-xs font-semibold bg-neutral-50 dark:bg-twilight-indigo-900/60 border border-neutral-300 text-neutral-800 dark:text-neutral-100">
      <span class="h-1.5 w-1.5 rounded-token-full bg-neutral-400" aria-hidden="true"></span>
      {dgettext("dashboard_automation_chat", "Paused")}
    </span>
    """
  end

  defp status_badge(%{status: :auto_disabled} = assigns) do
    ~H"""
    <span class="shrink-0 inline-flex items-center gap-1.5 rounded-token-full px-2.5 py-1 text-token-xs font-semibold bg-red-50 border border-red-200 text-red-700">
      <span class="h-1.5 w-1.5 rounded-token-full bg-red-500" aria-hidden="true"></span>
      {dgettext("dashboard_automation_chat", "Disabled")}
    </span>
    """
  end

  defp last_triggered_label(%{last_triggered_at: nil}, _time_format),
    do: dgettext("dashboard_automation_chat", "Never triggered")

  defp last_triggered_label(%{last_triggered_at: %DateTime{} = dt}, time_format) do
    dgettext("dashboard_automation_chat", "Last triggered %{time}",
      time: AutomationHelpers.format_datetime(dt, time_format)
    )
  end

  defp test_button_title(:active, true), do: dgettext("dashboard_automation_chat", "Testing...")

  defp test_button_title(:active, false),
    do: dgettext("dashboard_automation_chat", "Test Connection")

  defp test_button_title(_status, _testing),
    do: dgettext("dashboard_automation_chat", "Enable to test")

  # Renders the human-readable destination for the integration: workspace and
  # channel for OAuth installs, or "Custom webhook" with channel hint for
  # pasted Incoming Webhook URLs.
  defp location_label(%{app_mode: "oauth"} = integration) do
    workspace = integration.team_name || dgettext("dashboard_automation_chat", "Slack workspace")

    case integration.channel_name do
      nil ->
        workspace

      channel ->
        dgettext("dashboard_automation_chat", "%{workspace} · #%{channel}",
          workspace: workspace,
          channel: String.trim_leading(channel, "#")
        )
    end
  end

  defp location_label(%{app_mode: "webhook_url"} = integration) do
    case integration.webhook_channel_hint do
      nil ->
        dgettext("dashboard_automation_chat", "Custom webhook")

      "" ->
        dgettext("dashboard_automation_chat", "Custom webhook")

      hint ->
        dgettext("dashboard_automation_chat", "Custom webhook · #%{channel}",
          channel: String.trim_leading(hint, "#")
        )
    end
  end

  defp location_label(_integration), do: "Slack"

  defp disabled_reason_label(nil), do: dgettext("dashboard_automation_chat", "auto-disabled")
  defp disabled_reason_label(""), do: dgettext("dashboard_automation_chat", "auto-disabled")

  defp disabled_reason_label("webhook_url_revoked"),
    do: dgettext("dashboard_automation_chat", "webhook URL was revoked in Slack")

  defp disabled_reason_label(reason) when is_binary(reason), do: reason
end
