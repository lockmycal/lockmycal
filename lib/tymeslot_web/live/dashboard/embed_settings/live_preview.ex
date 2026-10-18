defmodule TymeslotWeb.Live.Dashboard.EmbedSettings.LivePreview do
  @moduledoc """
  Renders the live preview section for the embed settings dashboard.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Scheduling.LinkAccessPolicy
  alias TymeslotWeb.Components.CoreComponents.Icons
  alias TymeslotWeb.Live.Dashboard.EmbedSettings.Helpers

  @doc """
  Renders the live preview section.
  """
  attr :selected_embed_type, :string, required: true
  attr :username, :string, required: true
  attr :base_url, :string, required: true
  attr :preview_token, :string, required: true
  attr :embed_script_url, :string, required: true
  attr :embed_layout, :string, default: "column"
  attr :embed_locale, :string, default: ""
  attr :embed_meeting, :string, default: ""
  attr :embed_background, :string, default: ""
  attr :initial_height, :any, default: nil
  attr :max_width, :any, default: nil
  attr :is_ready, :boolean, required: true
  attr :error_reason, :any, required: true
  attr :myself, :any, required: true

  @spec live_preview(map()) :: Phoenix.LiveView.Rendered.t()
  def live_preview(assigns) do
    ~H"""
    <div class="bg-linear-to-br from-neutral-50 to-neutral-100 rounded-token-2xl border-2 border-neutral-200 p-8 dark:from-twilight-indigo-900/60 dark:to-twilight-indigo-900/40 dark:border-twilight-indigo-800">
      <div class="flex items-center mb-6">
        <div>
          <h2 class="text-token-lg font-semibold text-neutral-900 dark:text-neutral-50">
            {dgettext("dashboard_embed", "Test It Live")}
          </h2>
          <p class="text-neutral-600 mt-1 dark:text-neutral-300">
            {dgettext("dashboard_embed", "Try your booking widget in action")}
          </p>
        </div>
      </div>

      <div class="bg-white rounded-token-xl p-6 border-2 border-neutral-300 shadow-xl dark:bg-twilight-indigo-950 dark:border-twilight-indigo-700">
        <div class="text-center text-neutral-600 mb-4 dark:text-neutral-300">
          <p class="font-semibold text-primary-700 dark:text-primary-300">
            {dgettext("dashboard_embed", "Previewing: %{type} Mode",
              type: String.capitalize(@selected_embed_type)
            )}
          </p>
          <p class="text-token-sm">
            {dgettext(
              "dashboard_embed",
              "This is how your booking widget will appear on external sites"
            )}
          </p>
        </div>

        <%!-- Readiness Warning --%>
        <div
          :if={!@is_ready}
          class="mb-6 p-4 bg-amber-50 border-2 border-amber-200 rounded-token-xl flex items-start space-x-3 dark:bg-amber-950/40 dark:border-amber-800"
        >
          <Icons.icon name="hero-exclamation-triangle" class="w-6 h-6 text-amber-600 shrink-0" />
          <div>
            <p class="text-token-sm font-bold text-amber-900 dark:text-amber-200">
              {dgettext("dashboard_embed", "Link Deactivated")}
            </p>
            <p class="text-token-xs text-amber-800 dark:text-amber-200">
              {LinkAccessPolicy.reason_to_message(@error_reason)}
            </p>
          </div>
        </div>

        <%!-- The actual booking widget will be loaded here via JavaScript. The
             hook builds its own markup, so every string it shows arrives here
             already translated: the snippet labels in the embed's language, the
             rest in the dashboard's. `phx-update="ignore"` keeps the frame the
             hook built through every re-render of this component (switching
             tabs re-renders it); the data attributes still update, which is
             what the hook's `updated()` watches. --%>
        <div
          id="live-preview-container"
          phx-hook="EmbedPreview"
          phx-update="ignore"
          data-username={@username}
          data-base-url={@base_url}
          data-preview-token={@preview_token}
          data-embed-script-url={@embed_script_url}
          data-embed-type={@selected_embed_type}
          data-is-ready={to_string(@is_ready)}
          data-layout={@embed_layout}
          data-locale={@embed_locale}
          data-meeting={@embed_meeting}
          data-background={@embed_background}
          data-initial-height={@initial_height}
          data-max-width={@max_width}
          data-popup-label={Helpers.snippet_label("popup", %{locale: @embed_locale})}
          data-link-label={Helpers.snippet_label("link", %{locale: @embed_locale})}
          data-popup-hint={dgettext("dashboard_embed", "Click to test the booking modal")}
          data-link-hint={
            dgettext(
              "dashboard_embed",
              "Preview only: this link opens in test mode and stops working after an hour. Copy the link to share from the Embed Options tab."
            )
          }
          data-loading-message={
            dgettext(
              "dashboard_embed",
              "Booking widget is still loading. Please try again in a second."
            )
          }
          data-deactivated-message={
            dgettext(
              "dashboard_embed",
              "The preview is disabled because your booking link is currently deactivated."
            )
          }
          data-iframe-title={dgettext("dashboard_embed", "Booking Preview")}
          class="min-h-[400px] border-2 border-dashed border-neutral-200 rounded-token-lg flex items-center justify-center bg-neutral-50 overflow-hidden dark:border-twilight-indigo-800 dark:bg-twilight-indigo-900/60"
        >
        </div>
      </div>
    </div>
    """
  end
end
