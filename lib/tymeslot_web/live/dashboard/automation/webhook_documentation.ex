defmodule TymeslotWeb.Dashboard.Automation.WebhookDocumentation do
  @moduledoc """
  UI component for the webhook integration documentation section.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Webhooks

  @spec webhook_documentation(map()) :: Phoenix.LiveView.Rendered.t()
  def webhook_documentation(assigns) do
    ~H"""
    <.card
      icon="hero-book-open"
      title={dgettext("dashboard_automation", "Webhook Integration Guide")}
      description={
        dgettext(
          "dashboard_automation",
          "Connect %{app_name} to n8n, Zapier, Make, or your custom automation workflows",
          app_name: Config.app_name()
        )
      }
    >
      <div class="space-y-6">
        <%!-- What are webhooks --%>
        <div class="p-5 bg-linear-to-br from-primary-50 to-secondary-50 dark:from-primary-950/40 dark:to-secondary-950/40 rounded-token-2xl border-2 border-primary-100 dark:border-primary-800">
          <div class="flex items-start gap-3 mb-3">
            <div class="w-2 h-2 rounded-token-full bg-primary-500 animate-pulse mt-1.5"></div>
            <h3 class="text-token-base font-semibold text-neutral-900 dark:text-neutral-50">
              {dgettext("dashboard_automation", "What are webhooks?")}
            </h3>
          </div>
          <p class="text-neutral-700 font-medium ml-5 dark:text-neutral-200">
            {dgettext(
              "dashboard_automation",
              "Webhooks send real-time HTTP POST notifications to your automation tools whenever booking events occur. Perfect for triggering automated workflows, sending custom emails, syncing data, or building integrations."
            )}
          </p>
        </div>

        <%!-- Quick Setup --%>
        <div>
          <div class="flex items-start gap-3 mb-4">
            <div class="w-2 h-2 rounded-token-full bg-primary-500 animate-pulse mt-1.5"></div>
            <h3 class="text-token-base font-semibold text-neutral-900 dark:text-neutral-50">
              {dgettext("dashboard_automation", "Quick Setup with n8n")}
            </h3>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-3 ml-5">
            <%= for {step, step_index} <- Enum.with_index([
              {dgettext("dashboard_automation", "Create a workflow"),
               dgettext("dashboard_automation", "Start a new workflow in your n8n instance")},
              {dgettext("dashboard_automation", "Add webhook trigger"),
               dgettext("dashboard_automation", "Insert a Webhook node and copy its URL")},
              {dgettext("dashboard_automation", "Configure in %{app_name}",
                 app_name: Config.app_name()
               ),
               dgettext("dashboard_automation", "Create a webhook above and paste the URL")},
              {dgettext("dashboard_automation", "Select events"),
               dgettext("dashboard_automation", "Choose which booking events to monitor")},
              {dgettext("dashboard_automation", "Test connection"),
               dgettext("dashboard_automation", "Verify the webhook is working correctly")},
              {dgettext("dashboard_automation", "Build automation"),
               dgettext("dashboard_automation", "Add actions to process the webhook data")}
            ], 1) do %>
              <div class="flex items-start gap-3 p-3 bg-white rounded-token-xl border-2 border-neutral-100 hover:border-primary-200 transition-all dark:bg-twilight-indigo-950 dark:border-twilight-indigo-800">
                <div class="shrink-0 w-6 h-6 rounded-token-full bg-linear-to-br from-primary-500 to-secondary-500 text-white flex items-center justify-center text-xs font-black">
                  {step_index}
                </div>
                <div class="flex-1 min-w-0">
                  <div class="font-black text-neutral-900 text-token-sm dark:text-neutral-50">
                    {elem(step, 0)}
                  </div>
                  <div class="text-neutral-600 text-token-xs font-medium dark:text-neutral-300">
                    {elem(step, 1)}
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </div>

        <%!-- Available Events --%>
        <div>
          <div class="flex items-start gap-3 mb-4">
            <div class="w-2 h-2 rounded-token-full bg-primary-500 animate-pulse mt-1.5"></div>
            <h3 class="text-token-base font-semibold text-neutral-900 dark:text-neutral-50">
              {dgettext("dashboard_automation", "Available Events")}
            </h3>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-3 ml-5">
            <%!-- Every event a webhook can subscribe to, with the description
                  its form shows, so the guide never lists fewer. --%>
            <div
              :for={event <- Webhooks.available_events()}
              class="p-4 bg-white rounded-token-xl border-2 border-neutral-100 hover:border-primary-200 hover:shadow-md transition-all dark:bg-twilight-indigo-950 dark:border-twilight-indigo-800"
            >
              <div class="flex items-center gap-2 mb-2">
                <div class="p-1.5 bg-primary-50 rounded-token-lg dark:bg-primary-900/30">
                  <.icon name={event_icon(event.value)} class="w-4 h-4 text-primary-600" />
                </div>
                <code class="text-token-sm font-black text-neutral-900 dark:text-neutral-50">
                  {event.value}
                </code>
              </div>
              <p class="text-token-xs text-neutral-600 font-medium dark:text-neutral-300">
                {event.description}
              </p>
            </div>
          </div>
        </div>

        <%!-- Security --%>
        <div>
          <div class="flex items-start gap-3 mb-4">
            <div class="w-2 h-2 rounded-token-full bg-primary-500 animate-pulse mt-1.5"></div>
            <h3 class="text-token-base font-semibold text-neutral-900 dark:text-neutral-50">
              {dgettext("dashboard_automation", "Security & Authentication")}
            </h3>
          </div>
          <div class="ml-5 space-y-3">
            <div class="p-4 bg-neutral-50 rounded-token-xl border-2 border-neutral-100 dark:bg-twilight-indigo-900/60 dark:border-twilight-indigo-800">
              <div class="flex items-start gap-3">
                <div class="p-2 bg-white rounded-token-lg shrink-0 dark:bg-twilight-indigo-950">
                  <.icon name="hero-lock-closed" class="w-5 h-5 text-primary-600" />
                </div>
                <div class="flex-1">
                  <p class="text-neutral-700 font-medium mb-2 dark:text-neutral-200">
                    {dgettext(
                      "dashboard_automation",
                      "All webhook requests include a unique security token in the HTTP headers for verification:"
                    )}
                  </p>
                  <div class="grid grid-cols-1 md:grid-cols-2 gap-2">
                    <div class="flex items-center gap-2 p-2 bg-white rounded-token-lg dark:bg-twilight-indigo-950">
                      <code class="text-token-xs font-black text-primary-700 bg-primary-50 px-2 py-1 rounded dark:text-primary-300 dark:bg-primary-900/30">
                        X-Lockmycal-Token
                      </code>
                      <span class="text-token-xs text-neutral-600 font-medium dark:text-neutral-300">
                        {dgettext("dashboard_automation", "Security token")}
                      </span>
                    </div>
                    <div class="flex items-center gap-2 p-2 bg-white rounded-token-lg dark:bg-twilight-indigo-950">
                      <code class="text-token-xs font-black text-primary-700 bg-primary-50 px-2 py-1 rounded dark:text-primary-300 dark:bg-primary-900/30">
                        X-Lockmycal-Timestamp
                      </code>
                      <span class="text-token-xs text-neutral-600 font-medium dark:text-neutral-300">
                        {dgettext("dashboard_automation", "Request timestamp")}
                      </span>
                    </div>
                    <div class="flex items-center gap-2 p-2 bg-white rounded-token-lg dark:bg-twilight-indigo-950">
                      <code class="text-token-xs font-black text-primary-700 bg-primary-50 px-2 py-1 rounded dark:text-primary-300 dark:bg-primary-900/30">
                        X-Lockmycal-Delivery-Id
                      </code>
                      <span class="text-token-xs text-neutral-600 font-medium dark:text-neutral-300">
                        {dgettext("dashboard_automation", "Delivery ID")}
                      </span>
                    </div>
                  </div>
                  <p class="text-neutral-600 text-token-xs font-medium mt-2 dark:text-neutral-300">
                    {dgettext(
                      "dashboard_automation",
                      "Verify the token in your automation tool to ensure requests are from %{app_name}.",
                      app_name: Config.app_name()
                    )}
                  </p>
                  <p class="text-neutral-600 text-token-xs font-medium mt-2 dark:text-neutral-300">
                    {dgettext(
                      "dashboard_automation",
                      "The delivery ID is the same on every retry of one delivery and different for every other delivery. A failed or timed-out delivery can be retried, so your endpoint may receive the same event twice: record the delivery ID and ignore a request whose ID you have already processed."
                    )}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </.card>
    """
  end

  defp event_icon("meeting.created"), do: "hero-calendar"
  defp event_icon("meeting.requested"), do: "hero-hand-raised"
  defp event_icon("meeting.declined"), do: "hero-no-symbol"
  defp event_icon("meeting.request_expired"), do: "hero-clock"
  defp event_icon("meeting.cancelled"), do: "hero-x-mark"
  defp event_icon("meeting.rescheduled"), do: "hero-arrow-path"
  defp event_icon(_event), do: "hero-bolt"
end
