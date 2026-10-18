defmodule TymeslotWeb.Dashboard.Automation.DeliveryComponents do
  @moduledoc """
  The stats grid and delivery list shared by the webhook, Telegram and Slack
  delivery history modals.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Dashboard.Automation.Helpers, as: AutomationHelpers

  attr :stats, :map, default: nil

  @spec delivery_stats_grid(map()) :: Phoenix.LiveView.Rendered.t()
  def delivery_stats_grid(assigns) do
    ~H"""
    <%= if @stats do %>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-neutral-50 rounded-token-2xl p-4 border border-neutral-100 dark:bg-twilight-indigo-900/60 dark:border-twilight-indigo-800">
          <div class="text-token-xs font-black text-neutral-600 uppercase tracking-wider dark:text-twilight-indigo-300">
            {dgettext("dashboard_automation", "Total")}
          </div>
          <div class="text-token-3xl font-black text-neutral-900 mt-1 dark:text-neutral-50">
            {@stats.total}
          </div>
          <div class="text-token-xs text-neutral-500 font-medium mt-1 dark:text-twilight-indigo-300">
            {dngettext(
              "dashboard_automation",
              "Last %{days} day",
              "Last %{days} days",
              Map.get(@stats, :period_days, 7),
              days: Map.get(@stats, :period_days, 7)
            )}
          </div>
        </div>
        <div class="bg-green-50 rounded-token-2xl p-4 border border-green-100 dark:bg-green-950/40 dark:border-green-800">
          <div class="text-token-xs font-black text-green-600 uppercase tracking-wider dark:text-green-400">
            {dgettext("dashboard_automation", "Success")}
          </div>
          <div class="text-token-3xl font-black text-green-700 mt-1 dark:text-green-300">
            {@stats.successful}
          </div>
          <%= if Map.get(@stats, :success_rate) do %>
            <div class="text-token-xs text-green-600 font-medium mt-1 dark:text-green-400">
              {dgettext("dashboard_automation", "%{rate}% success rate", rate: @stats.success_rate)}
            </div>
          <% end %>
        </div>
        <div class="bg-red-50 rounded-token-2xl p-4 border border-red-100 dark:bg-red-950/40 dark:border-red-800">
          <div class="text-token-xs font-black text-red-600 uppercase tracking-wider dark:text-red-400">
            {dgettext("dashboard_automation", "Failed")}
          </div>
          <div class="text-token-3xl font-black text-red-700 mt-1 dark:text-red-300">
            {@stats.failed}
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  attr :deliveries, :list, required: true
  attr :time_format, :string, required: true

  @spec delivery_list(map()) :: Phoenix.LiveView.Rendered.t()
  def delivery_list(assigns) do
    ~H"""
    <%= if @deliveries == [] do %>
      <.empty_state
        icon="hero-paper-airplane"
        size={:sm}
        variant={:dashed}
        title={dgettext("dashboard_automation", "No deliveries yet")}
      />
    <% else %>
      <div class="space-y-3">
        <%= for delivery <- @deliveries do %>
          <div class="border-2 border-neutral-100 rounded-token-2xl p-4 hover:border-primary-100 hover:bg-primary-50/10 transition-colors dark:border-twilight-indigo-800 dark:hover:border-primary-800">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="flex flex-wrap items-center gap-3 mb-2">
                  <span class="bg-primary-50 text-primary-700 text-token-xs font-black px-2 py-1 rounded-token-lg border border-primary-100 dark:bg-primary-950/40 dark:text-primary-300 dark:border-primary-800">
                    {delivery.event_type}
                  </span>
                  <%= if delivery.response_status do %>
                    <.pill tone={response_tone(delivery.response_status)}>
                      {delivery.response_status}
                    </.pill>
                  <% end %>
                  <span class="text-token-xs text-neutral-500 font-medium dark:text-twilight-indigo-300">
                    {dgettext("dashboard_automation", "Attempt %{count}",
                      count: delivery.attempt_count
                    )}
                  </span>
                </div>
                <div class="text-token-sm text-neutral-600 font-medium flex items-center gap-1.5 dark:text-neutral-300">
                  <.icon name="hero-clock" class="w-4 h-4" />
                  {AutomationHelpers.format_datetime(delivery.inserted_at, @time_format)}
                </div>
                <%= if delivery.error_message do %>
                  <div class="text-token-sm text-red-600 font-medium mt-2 p-2 bg-red-50 rounded-token-lg border border-red-100 dark:bg-red-950/40 dark:border-red-800 dark:text-red-300">
                    {dgettext("dashboard_automation", "Error: %{message}",
                      message: delivery.error_message
                    )}
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp response_tone(status) when status >= 200 and status < 300, do: :success
  defp response_tone(_status), do: :danger
end
