defmodule TymeslotWeb.Components.Dashboard.Integrations.Video.CustomConfig.TemplatePreviewBox do
  @moduledoc """
  Preview box component for custom video URL template validation.

  Displays real-time feedback about template syntax with a stable, fixed-height layout
  that prevents any jumping or shifting when content changes.

  All states use an identical 3-row grid structure:
  - Row 1: Status label (fixed height)
  - Row 2: Message text (fixed height, may be empty)
  - Row 3: Preview code block (fixed height, may be hidden)
  """
  use Phoenix.Component

  @doc """
  Renders the template preview box.

  ## Attributes
    - status: :valid | :warning | :static | :empty
    - title: The status title/label (headline)
    - message: The description text (always present)
    - preview: Optional preview URL
  """
  attr :status, :atom, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true, doc: "Description text"
  attr :preview, :string, default: nil, doc: "Optional preview URL"

  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div class={[
      "h-28 sm:h-32 transition-none",
      preview_container_class(@status)
    ]}>
      <div class="h-full flex flex-col p-3 text-sm overflow-y-auto">
        <%!-- Row 1: Status Title (Always Present) --%>
        <div class={status_title_class(@status)}>
          {@title}
        </div>

        <%!-- Row 2: Description (Always Present) --%>
        <div class={message_class(@status)}>
          {@message}
        </div>

        <%!-- Row 3: Preview Code (With Top Margin) --%>
        <%= if @preview do %>
          <code class={preview_code_class(@status)}>
            {@preview}
          </code>
        <% else %>
          <div class="h-7 mt-2"></div>
        <% end %>
      </div>
    </div>
    """
  end

  # Container styling based on status
  defp preview_container_class(:valid),
    do:
      "rounded-lg border border-primary-200 dark:border-primary-800 bg-primary-50 dark:bg-primary-950/40"

  defp preview_container_class(:warning),
    do:
      "rounded-lg border border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-950/40"

  defp preview_container_class(:static),
    do:
      "rounded-lg border border-neutral-300 dark:border-twilight-indigo-800 bg-neutral-50 dark:bg-twilight-indigo-900/60"

  defp preview_container_class(:empty),
    do:
      "rounded-lg border border-neutral-300 dark:border-twilight-indigo-800 bg-neutral-50 dark:bg-twilight-indigo-900/60"

  # Title styling based on status
  defp status_title_class(:valid), do: "font-semibold text-primary-800 dark:text-primary-300"
  defp status_title_class(:warning), do: "font-semibold text-amber-800 dark:text-amber-200"
  defp status_title_class(:static), do: "font-medium text-neutral-700 dark:text-neutral-200"
  defp status_title_class(:empty), do: "text-neutral-500 dark:text-twilight-indigo-300 italic"

  # Message styling based on status
  defp message_class(:valid), do: "text-xs text-primary-700 dark:text-primary-300 leading-relaxed"

  defp message_class(:warning),
    do: "text-xs text-amber-700 dark:text-amber-300 leading-relaxed"

  defp message_class(:static),
    do: "text-xs text-neutral-600 dark:text-neutral-300 leading-relaxed"

  defp message_class(:empty),
    do: "text-xs text-neutral-500 dark:text-twilight-indigo-300 leading-relaxed italic"

  # Preview code styling based on status
  defp preview_code_class(:valid),
    do:
      "text-xs text-neutral-700 dark:text-neutral-200 bg-white dark:bg-twilight-indigo-950 px-2.5 py-1.5 rounded border border-primary-100 break-all font-mono block mt-2"

  defp preview_code_class(:warning),
    do:
      "text-xs text-neutral-700 dark:text-neutral-200 bg-white dark:bg-twilight-indigo-950 px-2.5 py-1.5 rounded border border-amber-100 break-all font-mono block mt-2"

  defp preview_code_class(_code), do: ""
end
