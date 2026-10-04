defmodule TymeslotWeb.Dashboard.Automation.Modals do
  @moduledoc """
  Modal components for automation settings.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.CoreComponents
  alias TymeslotWeb.Dashboard.Automation.Helpers, as: AutomationHelpers

  attr :show, :boolean, default: false
  attr :id, :string, default: "delete-webhook-modal"
  attr :on_cancel, :any, required: true
  attr :on_confirm, :any, required: true

  @spec delete_webhook_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def delete_webhook_modal(assigns) do
    ~H"""
    <CoreComponents.modal
      id={@id}
      show={@show}
      on_cancel={@on_cancel}
      size={:small}
    >
      <:header>
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>
          {dgettext("dashboard_automation", "Delete Webhook?")}
        </div>
      </:header>

      <div class="text-center sm:text-left">
        <p class="text-neutral-600 dark:text-neutral-300 font-medium">
          {dgettext(
            "dashboard_automation",
            "This action cannot be undone. All delivery logs for this webhook will also be deleted."
          )}
        </p>
      </div>

      <:footer>
        <div class="flex justify-end gap-3">
          <CoreComponents.action_button
            variant={:secondary}
            phx-click={@on_cancel}
          >
            {dgettext("dashboard_automation", "Cancel")}
          </CoreComponents.action_button>
          <CoreComponents.action_button
            variant={:danger}
            phx-click={@on_confirm}
          >
            {dgettext("dashboard_automation", "Delete Webhook")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  attr :show, :boolean, default: false
  attr :on_cancel, :any, required: true
  attr :on_confirm, :any, required: true

  @spec regenerate_token_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def regenerate_token_modal(assigns) do
    ~H"""
    <CoreComponents.modal
      id="regenerate-token-modal"
      show={@show}
      on_cancel={@on_cancel}
      size={:small}
    >
      <:header>
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>
          {dgettext("dashboard_automation", "Regenerate Token?")}
        </div>
      </:header>

      <div class="text-center sm:text-left">
        <p class="text-neutral-600 dark:text-neutral-300 font-medium">
          {dgettext(
            "dashboard_automation",
            "Are you sure? The current security token will be immediately invalidated and any existing integrations using it will stop working."
          )}
        </p>
      </div>

      <:footer>
        <div class="flex justify-end gap-3">
          <CoreComponents.action_button
            variant={:secondary}
            phx-click={@on_cancel}
          >
            {dgettext("dashboard_automation", "Cancel")}
          </CoreComponents.action_button>
          <CoreComponents.action_button
            variant={:danger}
            phx-click={@on_confirm}
          >
            {dgettext("dashboard_automation", "Regenerate")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  attr :show, :boolean, default: false
  attr :on_cancel, :any, required: true
  attr :on_confirm, :any, required: true

  @spec delete_telegram_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def delete_telegram_modal(assigns) do
    ~H"""
    <CoreComponents.modal
      id="delete-telegram-modal"
      show={@show}
      on_cancel={@on_cancel}
      size={:small}
    >
      <:header>
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>
          {dgettext("dashboard_automation", "Delete Telegram Integration?")}
        </div>
      </:header>

      <div class="text-center sm:text-left">
        <p class="text-neutral-600 dark:text-neutral-300 font-medium">
          {dgettext(
            "dashboard_automation",
            "This action cannot be undone. All delivery logs for this integration will also be deleted."
          )}
        </p>
      </div>

      <:footer>
        <div class="flex justify-end gap-3">
          <CoreComponents.action_button
            variant={:secondary}
            phx-click={@on_cancel}
          >
            {dgettext("dashboard_automation", "Cancel")}
          </CoreComponents.action_button>
          <CoreComponents.action_button
            variant={:danger}
            phx-click={@on_confirm}
          >
            {dgettext("dashboard_automation", "Delete Integration")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  attr :show, :boolean, default: false
  attr :webhook, :map, required: true
  attr :deliveries, :list, required: true
  attr :stats, :map, required: true
  attr :time_format, :string, required: true
  attr :on_close, :any, required: true

  @spec deliveries_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def deliveries_modal(assigns) do
    ~H"""
    <CoreComponents.modal
      id="deliveries-modal"
      show={@show}
      on_cancel={@on_close}
      size={:large}
    >
      <:header>
        <div class="flex flex-col">
          <span>{@webhook.name}</span>
          <span class="text-neutral-500 dark:text-twilight-indigo-300 font-medium font-mono text-token-xs mt-1">{@webhook.url}</span>
        </div>
      </:header>

      <div class="space-y-8">
        <.delivery_stats_grid stats={@stats} />

        <div>
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg font-black text-neutral-900 dark:text-neutral-50 flex items-center gap-2">
              <CoreComponents.icon name="hero-list-bullet" class="w-5 h-5" />
              {dgettext("dashboard_automation", "Recent Deliveries")}
            </h3>
            <div class="flex items-center gap-1.5 text-token-xs text-neutral-500 dark:text-twilight-indigo-300 font-medium bg-neutral-50 dark:bg-twilight-indigo-900/60 px-2 py-1 rounded-token-lg border border-neutral-300 dark:border-twilight-indigo-700">
              <CoreComponents.icon name="hero-information-circle" class="w-3.5 h-3.5" />
              {dgettext("dashboard_automation", "Test calls are not logged")}
            </div>
          </div>
          <.delivery_list deliveries={@deliveries} time_format={@time_format} />
        </div>
      </div>

      <:footer>
        <div class="flex justify-end">
          <CoreComponents.action_button variant={:primary} phx-click={@on_close}>
            {dgettext("dashboard_automation", "Close")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :integration, :map, required: true
  attr :deliveries, :list, required: true
  attr :stats, :map, default: nil
  attr :time_format, :string, required: true
  attr :on_close, :any, required: true

  @spec telegram_deliveries_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def telegram_deliveries_modal(assigns) do
    ~H"""
    <CoreComponents.modal id={@id} show={@show} on_cancel={@on_close} size={:large}>
      <:header>
        {dgettext("dashboard_automation", "Delivery History - %{name}", name: @integration.name)}
      </:header>

      <div class="space-y-8">
        <.delivery_stats_grid stats={@stats} />
        <.delivery_list deliveries={@deliveries} time_format={@time_format} />
      </div>

      <:footer>
        <div class="flex justify-end">
          <CoreComponents.action_button variant={:primary} phx-click={@on_close}>
            {dgettext("dashboard_automation", "Close")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  attr :show, :boolean, default: false
  attr :on_cancel, :any, required: true
  attr :on_confirm, :any, required: true

  @spec delete_slack_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def delete_slack_modal(assigns) do
    ~H"""
    <CoreComponents.modal
      id="delete-slack-modal"
      show={@show}
      on_cancel={@on_cancel}
      size={:small}
    >
      <:header>
        <div class="flex items-center gap-2">
          <svg class="w-5 h-5 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"
            />
          </svg>
          {dgettext("dashboard_automation", "Delete Slack Integration?")}
        </div>
      </:header>

      <div class="text-center sm:text-left">
        <p class="text-neutral-600 dark:text-neutral-300 font-medium">
          {dgettext(
            "dashboard_automation",
            "This action cannot be undone. All delivery logs for this integration will also be deleted."
          )}
        </p>
      </div>

      <:footer>
        <div class="flex justify-end gap-3">
          <CoreComponents.action_button
            variant={:secondary}
            phx-click={@on_cancel}
          >
            {dgettext("dashboard_automation", "Cancel")}
          </CoreComponents.action_button>
          <CoreComponents.action_button
            variant={:danger}
            phx-click={@on_confirm}
          >
            {dgettext("dashboard_automation", "Delete Integration")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :integration, :map, required: true
  attr :deliveries, :list, required: true
  attr :stats, :map, default: nil
  attr :time_format, :string, required: true
  attr :on_close, :any, required: true

  @spec slack_deliveries_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def slack_deliveries_modal(assigns) do
    ~H"""
    <CoreComponents.modal id={@id} show={@show} on_cancel={@on_close} size={:large}>
      <:header>
        {dgettext("dashboard_automation", "Delivery History - %{name}", name: @integration.name)}
      </:header>

      <div class="space-y-8">
        <.delivery_stats_grid stats={@stats} />
        <.delivery_list deliveries={@deliveries} time_format={@time_format} />
      </div>

      <:footer>
        <div class="flex justify-end">
          <CoreComponents.action_button variant={:primary} phx-click={@on_close}>
            {dgettext("dashboard_automation", "Close")}
          </CoreComponents.action_button>
        </div>
      </:footer>
    </CoreComponents.modal>
    """
  end

  # ============================================================================
  # Shared Delivery Components
  # ============================================================================

  attr :stats, :map, default: nil

  defp delivery_stats_grid(assigns) do
    ~H"""
    <%= if @stats do %>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-neutral-50 dark:bg-twilight-indigo-900/60 rounded-token-2xl p-4 border border-neutral-300 dark:border-twilight-indigo-800">
          <div class="text-token-xs font-black text-neutral-600 dark:text-neutral-300 uppercase tracking-wider">
            {dgettext("dashboard_automation", "Total")}
          </div>
          <div class="text-token-3xl font-black text-neutral-900 dark:text-neutral-50 mt-1">
            {@stats.total}
          </div>
          <div class="text-token-xs text-neutral-500 dark:text-twilight-indigo-300 font-medium mt-1">
            {dngettext(
              "dashboard_automation",
              "Last %{days} day",
              "Last %{days} days",
              Map.get(@stats, :period_days, 7),
              days: Map.get(@stats, :period_days, 7)
            )}
          </div>
        </div>
        <div class="bg-green-50 dark:bg-green-950/40 rounded-token-2xl p-4 border border-green-100 dark:border-green-800">
          <div class="text-token-xs font-black text-green-600 dark:text-green-300 uppercase tracking-wider">
            {dgettext("dashboard_automation", "Success")}
          </div>
          <div class="text-token-3xl font-black text-green-700 dark:text-green-300 mt-1">
            {@stats.successful}
          </div>
          <%= if Map.get(@stats, :success_rate) do %>
            <div class="text-token-xs text-green-600 dark:text-green-300 font-medium mt-1">
              {dgettext("dashboard_automation", "%{rate}% success rate", rate: @stats.success_rate)}
            </div>
          <% end %>
        </div>
        <div class="bg-red-50 dark:bg-red-950/40 rounded-token-2xl p-4 border border-red-100 dark:border-red-800">
          <div class="text-token-xs font-black text-red-600 dark:text-red-300 uppercase tracking-wider">
            {dgettext("dashboard_automation", "Failed")}
          </div>
          <div class="text-token-3xl font-black text-red-700 dark:text-red-300 mt-1">
            {@stats.failed}
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  attr :deliveries, :list, required: true
  attr :time_format, :string, required: true

  defp delivery_list(assigns) do
    ~H"""
    <%= if @deliveries == [] do %>
      <div class="text-center py-12 bg-neutral-50 dark:bg-twilight-indigo-900/60 rounded-token-2xl border-2 border-dashed border-neutral-300 dark:border-twilight-indigo-800">
        <p class="text-neutral-600 dark:text-neutral-300 font-medium">
          {dgettext("dashboard_automation", "No deliveries yet")}
        </p>
      </div>
    <% else %>
      <div class="space-y-3">
        <%= for delivery <- @deliveries do %>
          <div class="border-2 border-neutral-300 dark:border-twilight-indigo-800 rounded-token-2xl p-4 hover:border-primary-100 dark:hover:border-primary-800 hover:bg-primary-50/10 dark:hover:bg-primary-950/10 transition-colors">
            <div class="flex items-start justify-between">
              <div class="flex-1">
                <div class="flex flex-wrap items-center gap-3 mb-2">
                  <span class="bg-primary-50 dark:bg-primary-950/40 text-primary-700 dark:text-primary-300 text-token-xs font-black px-2 py-1 rounded-token-lg border border-primary-100 dark:border-primary-800">
                    {delivery.event_type}
                  </span>
                  <%= if delivery.response_status do %>
                    <span class={[
                      "text-token-xs font-black px-2 py-1 rounded-token-lg border",
                      if(delivery.response_status >= 200 and delivery.response_status < 300,
                        do:
                          "bg-green-50 dark:bg-green-950/40 text-green-700 dark:text-green-300 border-green-100 dark:border-green-800",
                        else:
                          "bg-red-50 dark:bg-red-950/40 text-red-700 dark:text-red-300 border-red-100 dark:border-red-800"
                      )
                    ]}>
                      {delivery.response_status}
                    </span>
                  <% end %>
                  <span class="text-token-xs text-neutral-500 dark:text-twilight-indigo-300 font-medium">
                    {dgettext("dashboard_automation", "Attempt %{count}",
                      count: delivery.attempt_count
                    )}
                  </span>
                </div>
                <div class="text-token-sm text-neutral-600 dark:text-neutral-300 font-medium flex items-center gap-1.5">
                  <CoreComponents.icon name="hero-clock" class="w-4 h-4" />
                  {AutomationHelpers.format_datetime(delivery.inserted_at, @time_format)}
                </div>
                <%= if delivery.error_message do %>
                  <div class="text-token-sm text-red-600 dark:text-red-300 font-medium mt-2 p-2 bg-red-50 dark:bg-red-950/40 rounded-token-lg border border-red-100 dark:border-red-800">
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
end
