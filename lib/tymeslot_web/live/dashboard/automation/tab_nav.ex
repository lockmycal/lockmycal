defmodule TymeslotWeb.Dashboard.Automation.TabNav do
  @moduledoc """
  Tab bar for `TymeslotWeb.Dashboard.AutomationSettingsComponent`.

  Renders one button per integration channel and pushes `switch_tab` back to the
  owning LiveComponent through the `:myself` target passed in by the caller.
  Telegram renders as a disabled placeholder when the integration is switched
  off; Slack is omitted entirely.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Icons.IconComponents

  attr :active_tab, :atom, required: true
  attr :telegram_enabled, :boolean, required: true
  attr :slack_enabled, :boolean, required: true
  attr :myself, :any, required: true

  @spec tab_nav(map()) :: Phoenix.LiveView.Rendered.t()
  def tab_nav(assigns) do
    ~H"""
    <div class="flex bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-2xl p-1.5 shadow-sm max-w-fit mb-10">
      <button
        phx-click={JS.push("switch_tab", value: %{"tab" => "webhooks"}, target: @myself)}
        class={tab_class(@active_tab == :webhooks)}
      >
        <IconComponents.icon name={:webhook} class="w-5 h-5" />
        <span>{dgettext("dashboard_automation", "Webhooks")}</span>
      </button>

      <%= if @telegram_enabled do %>
        <button
          phx-click={JS.push("switch_tab", value: %{"tab" => "telegram"}, target: @myself)}
          class={tab_class(@active_tab == :telegram)}
        >
          <IconComponents.icon name={:telegram} class="w-5 h-5" />
          <span>{dgettext("dashboard_automation", "Telegram")}</span>
        </button>
      <% else %>
        <div class="flex items-center space-x-2 px-6 py-2.5 rounded-token-xl text-token-sm font-black text-neutral-300 opacity-60 cursor-not-allowed">
          <IconComponents.icon name={:telegram} class="w-5 h-5" />
          <span>{dgettext("dashboard_automation", "Telegram")}</span>
          <span class="ml-1 text-token-2xs bg-neutral-100 px-2 py-0.5 rounded-full uppercase tracking-tighter">
            {dgettext("dashboard_automation_chat", "Disabled")}
          </span>
        </div>
      <% end %>

      <%= if @slack_enabled do %>
        <button
          phx-click={JS.push("switch_tab", value: %{"tab" => "slack"}, target: @myself)}
          class={tab_class(@active_tab == :slack)}
        >
          <IconComponents.icon name={:slack} class="w-5 h-5" />
          <span>{dgettext("dashboard_automation", "Slack")}</span>
        </button>
      <% end %>
    </div>
    """
  end

  defp tab_class(true) do
    "flex items-center space-x-2 px-6 py-2.5 rounded-token-xl text-token-sm font-black transition-all duration-300 cursor-pointer bg-linear-to-br from-primary-600 to-secondary-600 text-white"
  end

  defp tab_class(false) do
    "flex items-center space-x-2 px-6 py-2.5 rounded-token-xl text-token-sm font-black transition-all duration-300 cursor-pointer text-neutral-500 dark:text-neutral-400 hover:text-primary-600 hover:bg-primary-50 dark:hover:bg-twilight-indigo-900"
  end
end
