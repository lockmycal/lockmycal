defmodule TymeslotWeb.Dashboard.ThemeSettings.ThemePreview do
  @moduledoc """
  UI component for rendering theme previews.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Themes.Core.ThemeInfo

  @doc """
  Renders a preview for a specific theme.
  """
  attr :theme_id, :string, required: true

  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    theme = ThemeInfo.get_theme(assigns.theme_id)
    assigns = assign(assigns, :theme, theme)

    ~H"""
    <%= if @theme do %>
      <div class="w-full h-full bg-neutral-100 rounded-token-lg overflow-hidden">
        <img
          src={@theme.preview_image}
          alt={
            dgettext("dashboard_appearance", "%{theme_name} Theme Preview", theme_name: @theme.name)
          }
          class="w-full h-full object-cover transition-transform duration-300 hover:scale-105"
          data-img-fallback
        />
        <%!-- Fallback content when image fails to load --%>
        <div
          class="w-full h-full bg-linear-to-br from-neutral-100 to-primary-50 flex items-center justify-center"
          style="display: none;"
        >
          <div class="text-center p-4">
            <div class="w-12 h-12 bg-primary-500 rounded-token-lg mx-auto mb-3 flex items-center justify-center">
              <.icon name="hero-photo" class="w-6 h-6 text-white" />
            </div>
            <p class="text-token-sm font-semibold text-neutral-700 dark:text-neutral-200">
              {dgettext("dashboard_appearance", "%{theme_name} Theme", theme_name: @theme.name)}
            </p>
            <p class="text-token-xs text-neutral-600 dark:text-neutral-300">{@theme.description}</p>
          </div>
        </div>
      </div>
    <% else %>
      <div class="w-full h-full bg-neutral-100 flex items-center justify-center rounded-token-lg dark:bg-twilight-indigo-800">
        <div class="text-center text-neutral-500 dark:text-twilight-indigo-300">
          <.icon name="hero-photo" class="w-12 h-12 mx-auto mb-2" />
          <div class="text-token-sm">{dgettext("dashboard_appearance", "Theme Preview")}</div>
        </div>
      </div>
    <% end %>
    """
  end
end
