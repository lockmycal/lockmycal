defmodule TymeslotWeb.Components.CoreComponents.Modal do
  @moduledoc "Modal components extracted from CoreComponents."
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  # Phoenix modules
  alias Phoenix.LiveView.JS

  # ========== MODAL ==========

  @doc """
  Renders a modal dialog with glassmorphism styling.

  ## Examples

      # Default medium size
      <.modal id="confirm-modal" show={@show_modal}>
        <:header>Are you sure?</:header>
        This action cannot be undone.
        <:footer>
          <.action_button variant={:secondary} phx-click={JS.hide(to: "#confirm-modal")}>
            Cancel
          </.action_button>
          <.action_button variant={:danger} phx-click="delete">
            Delete
          </.action_button>
        </:footer>
      </.modal>

      # With a line of explanation under the title
      <.modal id="venue-modal" show={@show_modal}>
        <:header>Add location</:header>
        <:subtitle>A place you meet people.</:subtitle>
        <%!-- Form content here --%>
      </.modal>

      # Small modal
      <.modal id="small-modal" show={@show_modal} size={:small}>
        <:header>Quick Note</:header>
        Your changes have been saved.
      </.modal>

      # Large modal for forms
      <.modal id="form-modal" show={@show_modal} size={:large}>
        <:header>Edit Profile</:header>
        <%!-- Form content here --%>
      </.modal>

      # Extra large modal for complex content
      <.modal id="details-modal" show={@show_modal} size={:xlarge}>
        <:header>Meeting Details</:header>
        <%!-- Detailed content here --%>
      </.modal>

      # A strip under the title, above the header's divider (e.g. mode tabs)
      <.modal id="create-modal" show={@show_modal}>
        <:header>New item</:header>
        <:subheader><%!-- tabs --%></:subheader>
        <%!-- Form content here --%>
      </.modal>

      # Full screen modal
      <.modal id="full-modal" show={@show_modal} size={:full}>
        <:header>Full Screen View</:header>
        <%!-- Full screen content here --%>
      </.modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}, doc: "JS command executed when the modal is dismissed"

  attr :size, :atom,
    default: :medium,
    values: [:xsmall, :small, :medium, :large, :xlarge, :full]

  attr :aria_label, :string,
    default: nil,
    doc: "Accessible name for the dialog when no :header slot is rendered"

  slot :header, required: false

  slot :subheader,
    required: false,
    doc: "rendered under the header's title row, above its divider; needs :header"

  slot :subtitle,
    required: false,
    doc: "A line of explanation under the header; rendered only with a :header"

  slot :inner_block, required: true
  slot :footer, required: false

  @spec modal(map()) :: Phoenix.LiveView.Rendered.t()
  def modal(assigns) do
    assigns = assign(assigns, :dialog_label_attrs, dialog_label_attrs(assigns))

    ~H"""
    <div
      id={@id}
      class="modal-overlay"
      style={if @show, do: "display: flex;", else: "display: none;"}
      phx-window-keydown={@on_cancel}
      phx-key="escape"
      phx-hook="ModalFocusTrap"
    >
      <div class="modal-container p-6">
        <div
          id={"#{@id}-content"}
          class={
            [
              # Scrolling and the height cap belong to `.modal-content` in
              # modal.css; an `overflow-hidden` here would win over it and cut a
              # tall dialog off again.
              "modal-content bg-white rounded-4xl shadow-2xl border-2 border-neutral-300 relative",
              modal_size_class(@size)
            ]
          }
          role="dialog"
          aria-modal="true"
          {@dialog_label_attrs}
          tabindex="-1"
          phx-click-away={if @show, do: @on_cancel}
        >
          <%!-- Header --%>
          <%= if @header != [] do %>
            <div class={[
              "modal-header px-8 py-6 border-b-2 border-neutral-300 flex justify-between gap-4",
              if(@subtitle == [], do: "items-center", else: "items-start"),
              @subheader != [] && "modal-header--with-subheader"
            ]}>
              <%!-- Takes the row's free width, so a title that is an input
                    (an editable name) can fill it up to the close button. --%>
              <div class="flex-1 min-w-0">
                <h3
                  id={"#{@id}-title"}
                  class="modal-title text-2xl font-black text-neutral-900 dark:text-neutral-50 tracking-tight"
                >
                  {render_slot(@header)}
                </h3>
                <p
                  :if={@subtitle != []}
                  id={"#{@id}-subtitle"}
                  class="mt-1 text-token-sm font-medium text-neutral-500 dark:text-neutral-400"
                >
                  {render_slot(@subtitle)}
                </p>
              </div>
              <button
                type="button"
                class="modal-icon-button"
                aria-label={dgettext("common", "Close modal")}
                phx-click={@on_cancel}
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    stroke-width="2.5"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>
            <div
              :if={@subheader != []}
              class="modal-subheader px-8 pb-6 border-b-2 border-neutral-300"
            >
              {render_slot(@subheader)}
            </div>
          <% end %>

          <%!-- Body --%>
          <%!-- `scrollable` is the app's own scrollbar styling, shared with
                the body and the other scrolling panels. --%>
          <div class="modal-body scrollable p-8">
            {render_slot(@inner_block)}
          </div>

          <%!-- Footer --%>
          <%= if @footer != [] do %>
            <div class="modal-footer px-8 py-6 bg-neutral-50/50 border-t-2 border-neutral-300">
              {render_slot(@footer)}
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Prefer aria-labelledby (pointing at the rendered header slot); fall back to
  # the caller-supplied aria-label when there is no header to label the dialog.
  defp dialog_label_attrs(%{header: header, subtitle: subtitle, id: id}) when header != [] do
    attrs = %{"aria-labelledby" => "#{id}-title"}
    if subtitle == [], do: attrs, else: Map.put(attrs, "aria-describedby", "#{id}-subtitle")
  end

  defp dialog_label_attrs(%{aria_label: aria_label}) do
    %{"aria-label" => aria_label}
  end

  # Helper function for modal size classes
  defp modal_size_class(:xsmall), do: "modal-content--xsmall"
  defp modal_size_class(:small), do: "modal-content--small"
  defp modal_size_class(:medium), do: "modal-content--medium"
  defp modal_size_class(:large), do: "modal-content--large"
  defp modal_size_class(:xlarge), do: "modal-content--xlarge"
  defp modal_size_class(:full), do: "modal-content--full"
  defp modal_size_class(_other), do: "modal-content--medium"
end
