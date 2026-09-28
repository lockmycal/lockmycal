defmodule TymeslotWeb.Dashboard.Automation.WebhookCard do
  @moduledoc """
  UI component for displaying a single webhook card.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Webhooks.DeliveryStatus
  alias TymeslotWeb.Components.Icons.IconComponents
  alias TymeslotWeb.Components.UI.StatusSwitch
  alias TymeslotWeb.Dashboard.Automation.Helpers

  attr :webhook, :map, required: true
  attr :time_format, :string, required: true
  attr :testing, :boolean, default: false
  attr :target, :any, required: true
  attr :on_edit, :any, required: true
  attr :on_delete, :any, required: true
  attr :on_toggle, :string, required: true
  attr :on_test, :any, required: true
  attr :on_view_deliveries, :any, required: true

  @spec webhook_card(map()) :: Phoenix.LiveView.Rendered.t()
  def webhook_card(assigns) do
    ~H"""
    <div class={[
      "card-glass p-4",
      if(@webhook.is_active, do: "card-glass-available", else: "card-glass-unavailable")
    ]}>
      <div class="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
        <div class="flex min-w-0 flex-1 items-center gap-4">
          <IconComponents.icon
            name={:webhook}
            class="w-5 h-5 text-neutral-600 dark:text-neutral-300 shrink-0"
          />

          <div class="min-w-0 flex-1">
            <h3 class="truncate text-token-base font-semibold text-neutral-800 dark:text-neutral-100">
              {@webhook.name}
            </h3>
            <p class="mt-0.5 truncate text-token-sm text-neutral-500 font-mono">
              {@webhook.url}
            </p>
            <p :if={@webhook.disabled_reason} class="mt-0.5 text-token-xs text-red-600 font-medium">
              {dgettext("dashboard_automation", "Disabled: %{reason}",
                reason: @webhook.disabled_reason
              )}
            </p>
            <div class="mt-1.5 flex flex-wrap items-center gap-x-3 gap-y-1 text-token-xs text-neutral-500">
              <span :for={event <- @webhook.events} class="inline-flex items-center gap-1">
                <div class={[
                  "w-1.5 h-1.5 rounded-full",
                  if(@webhook.is_active, do: "bg-primary-500", else: "bg-neutral-300")
                ]} />
                {event}
              </span>
              <span class="inline-flex items-center gap-1 text-neutral-400">
                <.icon name="hero-clock" class="w-3.5 h-3.5" />
                {last_triggered_time_label(@webhook, @time_format)}
                <span :if={@webhook.last_status} class={status_color(@webhook.last_status)}>
                  ({status_label(@webhook.last_status)})
                </span>
              </span>
            </div>
          </div>

          <span
            :if={!@webhook.is_active}
            class="shrink-0 inline-flex items-center gap-1.5 rounded-token-full px-2.5 py-1 text-token-xs font-semibold bg-neutral-50 dark:bg-twilight-indigo-900/60 border border-neutral-300 text-neutral-800 dark:text-neutral-100"
          >
            <span class="h-1.5 w-1.5 rounded-token-full bg-neutral-400" aria-hidden="true"></span>
            {dgettext("dashboard_automation", "Disabled")}
          </span>
        </div>

        <div class="flex flex-wrap items-center gap-2 sm:justify-end">
          <StatusSwitch.status_switch
            id={"webhook-toggle-#{@webhook.id}"}
            checked={@webhook.is_active}
            on_change={@on_toggle}
            target={@target}
            phx_value_id={"#{@webhook.id}"}
            size={:small}
            show_icon={false}
          />

          <button
            phx-click={@on_test}
            disabled={@testing || !@webhook.is_active}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={test_button_title(@webhook.is_active, @testing)}
            aria-label={test_button_title(@webhook.is_active, @testing)}
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
            title={dgettext("dashboard_automation", "View Delivery Logs")}
            aria-label={dgettext("dashboard_automation", "View Delivery Logs")}
          >
            <.icon name="hero-document-text" class="w-5 h-5" />
          </button>

          <button
            phx-click={@on_edit}
            class="row-action-button row-action-button--icon-only row-action-button--neutral"
            title={dgettext("dashboard_automation", "Edit Webhook")}
            aria-label={dgettext("dashboard_automation", "Edit Webhook")}
          >
            <.icon name="hero-pencil-square" class="w-5 h-5" />
          </button>

          <button
            phx-click={@on_delete}
            class="row-action-button row-action-button--danger"
            title={dgettext("dashboard_automation", "Delete Webhook")}
            aria-label={dgettext("dashboard_automation", "Delete Webhook")}
          >
            <.icon name="hero-trash" class="w-5 h-5" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp status_color(last_status) do
    case DeliveryStatus.state(last_status) do
      :success -> "text-green-600 font-bold"
      :failed -> "text-red-600 font-bold"
      :unknown -> "text-neutral-600 font-medium"
    end
  end

  # The raw reason (e.g. "HTTP 500", "connection refused") is machine
  # diagnostic text, not UI copy, so only the state word is translated; the
  # reason is interpolated untranslated, same as the disabled-reason badge.
  defp status_label(last_status) do
    case DeliveryStatus.state(last_status) do
      :success ->
        dgettext("dashboard_automation", "Succeeded")

      :failed ->
        case DeliveryStatus.reason(last_status) do
          nil -> dgettext("dashboard_automation", "Failed")
          reason -> dgettext("dashboard_automation", "Failed: %{reason}", reason: reason)
        end

      :unknown ->
        last_status
    end
  end

  # Time-only half of "last triggered" — the status half (colour + label)
  # renders as its own span in the template so it can be colour-coded via
  # `status_color/1`, which a single interpolated string can't carry.
  defp last_triggered_time_label(%{last_triggered_at: nil}, _time_format),
    do: dgettext("dashboard_automation", "Never triggered")

  defp last_triggered_time_label(%{last_triggered_at: %DateTime{} = dt}, time_format) do
    dgettext("dashboard_automation", "Last triggered %{time}",
      time: Helpers.format_datetime(dt, time_format)
    )
  end

  defp test_button_title(false, _testing),
    do: dgettext("dashboard_automation", "Enable webhook to test")

  defp test_button_title(true, true), do: dgettext("dashboard_automation", "Testing...")
  defp test_button_title(true, false), do: dgettext("dashboard_automation", "Test Connection")
end
