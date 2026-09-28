defmodule TymeslotWeb.Dashboard.Automation.TelegramCard do
  @moduledoc false
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

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
  attr :on_disconnect, :any, default: nil
  attr :on_reconnect, :any, default: nil

  @spec telegram_card(map()) :: Phoenix.LiveView.Rendered.t()
  def telegram_card(assigns) do
    ~H"""
    <div class={[
      "card-glass p-4",
      if(@integration.status == :active, do: "card-glass-available", else: "card-glass-unavailable")
    ]}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
        <div class="flex min-w-0 flex-1 items-center gap-4">
          <IconComponents.icon
            name={:telegram}
            class="w-5 h-5 text-neutral-600 dark:text-neutral-300 shrink-0"
          />

          <div class="min-w-0 flex-1">
            <h3 class="truncate text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
              {@integration.name}
            </h3>
            <p
              :if={@integration.chat_id}
              class="mt-0.5 truncate text-token-sm text-neutral-500 font-mono"
            >
              {dgettext("dashboard_automation_chat", "Chat: %{chat_id}",
                chat_id: truncate_chat_id(@integration.chat_id)
              )}
            </p>
            <div class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-token-xs text-neutral-500">
              <%= if @integration.status == :pending_link do %>
                <span class="text-amber-600 font-medium">
                  {dgettext(
                    "dashboard_automation_chat",
                    "Connect Telegram to start receiving notifications."
                  )}
                </span>
              <% else %>
                <span :for={event <- @integration.events} class="inline-flex items-center gap-1">
                  <div class={[
                    "w-1.5 h-1.5 rounded-full",
                    if(@integration.status == :active, do: "bg-primary-500", else: "bg-neutral-300")
                  ]} />
                  {event}
                </span>
                <span class="inline-flex items-center gap-1 text-neutral-400">
                  <.icon name="hero-clock" class="w-3.5 h-3.5" />
                  {last_triggered_label(@integration, @time_format)}
                </span>
                <span :if={@integration.status == :auto_disabled} class="text-red-600 font-medium">
                  {dgettext("dashboard_automation_chat", "Disabled: %{reason}",
                    reason: disabled_reason_label(@integration.disabled_reason)
                  )}
                </span>
              <% end %>
            </div>
          </div>

          <.status_badge status={@integration.status} />
        </div>

        <div class="flex flex-wrap items-center gap-2 sm:justify-end">
          <StatusSwitch.status_switch
            :if={@integration.status in [:active, :paused]}
            id={"telegram-toggle-#{@integration.id}"}
            checked={@integration.is_active}
            on_change={@on_toggle}
            target={@target}
            phx_value_id={"#{@integration.id}"}
            size={:small}
            show_icon={false}
          />

          <button
            :if={
              @integration.status == :pending_link && @integration.bot_mode == "shared" &&
                @on_reconnect
            }
            phx-click={@on_reconnect}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Connect")}
            aria-label={dgettext("dashboard_automation_chat", "Connect")}
          >
            <.icon name="hero-link" class="w-5 h-5" />
          </button>

          <button
            :if={@integration.status == :auto_disabled && @on_reenable}
            phx-click={@on_reenable}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Re-enable")}
            aria-label={dgettext("dashboard_automation_chat", "Re-enable")}
          >
            <.icon name="hero-arrow-path" class="w-5 h-5" />
          </button>

          <button
            :if={@integration.status in [:active, :paused]}
            phx-click={@on_test}
            disabled={@testing || @integration.status != :active}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={test_button_title(@integration.status, @testing)}
            aria-label={test_button_title(@integration.status, @testing)}
          >
            <%= if @testing do %>
              <.spinner class="w-5 h-5" />
            <% else %>
              <.icon name="hero-bolt" class="w-5 h-5" />
            <% end %>
          </button>

          <button
            phx-click={@on_view_deliveries}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "View delivery logs")}
            aria-label={dgettext("dashboard_automation_chat", "View delivery logs")}
          >
            <.icon name="hero-document-text" class="w-5 h-5" />
          </button>

          <button
            :if={@integration.status != :pending_link}
            phx-click={@on_edit}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Edit")}
            aria-label={dgettext("dashboard_automation_chat", "Edit")}
          >
            <.icon name="hero-pencil-square" class="w-5 h-5" />
          </button>

          <button
            :if={@on_disconnect && @integration.bot_mode == "shared" && @integration.chat_id}
            phx-click={@on_disconnect}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation_chat", "Disconnect Telegram")}
            aria-label={dgettext("dashboard_automation_chat", "Disconnect Telegram")}
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

  defp status_badge(%{status: :pending_link} = assigns) do
    ~H"""
    <span class="shrink-0 inline-flex items-center gap-1.5 rounded-token-full px-2.5 py-1 text-token-xs font-semibold bg-amber-50 border border-amber-200 text-amber-700">
      <span class="h-1.5 w-1.5 rounded-token-full bg-amber-500 animate-pulse" aria-hidden="true"></span>
      {dgettext("dashboard_automation_chat", "Awaiting connection")}
    </span>
    """
  end

  defp status_badge(%{status: :active} = assigns) do
    ~H"""
    <span class="shrink-0 inline-flex items-center gap-1.5 rounded-token-full px-2.5 py-1 text-token-xs font-semibold bg-emerald-50 border border-emerald-200 text-emerald-700">
      <span class="h-1.5 w-1.5 rounded-token-full bg-emerald-500" aria-hidden="true"></span>
      {dgettext("dashboard_automation_chat", "Connected")}
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

  defp disabled_reason_label(nil), do: dgettext("dashboard_automation_chat", "auto-disabled")
  defp disabled_reason_label(""), do: dgettext("dashboard_automation_chat", "auto-disabled")

  defp disabled_reason_label("invalid_token"),
    do: dgettext("dashboard_automation_chat", "bot token was rejected")

  defp disabled_reason_label("bot_blocked"),
    do: dgettext("dashboard_automation_chat", "bot was blocked by the user")

  defp disabled_reason_label("bot_kicked"),
    do: dgettext("dashboard_automation_chat", "bot was kicked from the group")

  defp disabled_reason_label("chat_unreachable"),
    do: dgettext("dashboard_automation_chat", "chat is no longer reachable")

  defp disabled_reason_label("too_many_failures"),
    do: dgettext("dashboard_automation_chat", "too many consecutive delivery failures")

  defp disabled_reason_label("rate_limited"),
    do: dgettext("dashboard_automation_chat", "repeatedly rate-limited by Telegram")

  defp disabled_reason_label(reason) when is_binary(reason), do: reason

  defp truncate_chat_id(chat_id) when is_binary(chat_id) do
    if String.length(chat_id) > 12 do
      String.slice(chat_id, 0, 12) <> "..."
    else
      chat_id
    end
  end
end
