defmodule TymeslotWeb.Dashboard.Automation.SlackEmptyState do
  @moduledoc false
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.Icons.IconComponents

  attr :oauth_mode_available?, :boolean, required: true
  attr :oauth_start_path, :string, required: true
  attr :on_use_webhook_url, :any, required: true

  @spec slack_empty_state(map()) :: Phoenix.LiveView.Rendered.t()
  def slack_empty_state(assigns) do
    ~H"""
    <div class="card-glass text-center py-16">
      <div class="w-20 h-20 bg-primary-50 rounded-token-3xl mx-auto mb-6 flex items-center justify-center border-2 border-primary-100">
        <IconComponents.icon name={:slack} class="w-10 h-10 text-primary-600" />
      </div>

      <h3 class="text-token-2xl font-black text-neutral-900 dark:text-neutral-50 mb-3">
        {dgettext("dashboard_automation_chat", "No Slack Integrations")}
      </h3>
      <p class="text-neutral-600 dark:text-neutral-300 font-medium mb-8 max-w-md mx-auto">
        {dgettext(
          "dashboard_automation_chat",
          "Connect Slack to receive instant notifications when meetings are booked, cancelled, or rescheduled."
        )}
      </p>

      <%= if @oauth_mode_available? do %>
        <div class="flex flex-col sm:flex-row items-center justify-center gap-3">
          <.link href={@oauth_start_path} class="btn btn-primary inline-flex items-center gap-2">
            <IconComponents.icon name={:slack} class="w-5 h-5" />
            {dgettext("dashboard_automation_chat", "Add to Slack")}
          </.link>
          <button
            phx-click={@on_use_webhook_url}
            class="inline-flex items-center gap-2 px-5 py-3 rounded-token-xl border-2 bg-white dark:bg-twilight-indigo-950 border-neutral-300 text-neutral-700 dark:text-neutral-200 hover:border-primary-200 hover:bg-primary-50 font-bold transition-all"
          >
            {dgettext("dashboard_automation_chat", "Add via webhook URL")}
          </button>
        </div>
      <% else %>
        <button phx-click={@on_use_webhook_url} class="btn btn-primary">
          {dgettext("dashboard_automation_chat", "Add Slack via Webhook URL")}
        </button>
      <% end %>
    </div>
    """
  end
end
