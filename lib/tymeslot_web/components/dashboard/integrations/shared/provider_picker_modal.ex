defmodule TymeslotWeb.Components.Dashboard.Integrations.Shared.ProviderPickerModal do
  @moduledoc """
  Modal that drives the whole "add an integration" flow.

  It has two states, both rendered inside the same dialog:

    * **picker** — a compact grid of the available providers, grouped into
      optional sections (e.g. OAuth vs CalDAV servers). Selecting a provider
      dispatches its `click_event` (`connect_provider` / `setup_provider`) back
      to `@target`.
    * **config** — when `config_active` is true the provider's setup form is
      rendered in place via the `:config` slot, so the credentials/discovery
      steps happen in the modal rather than on a separate page. A Back control
      returns to the picker via `back_event`.

  Stateless — visibility (`show`), the selected provider, and every event are
  owned by the parent settings LiveComponent.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  import TymeslotWeb.Components.Icons.ProviderIcon

  @typedoc """
  A single selectable provider tile:

    * `:provider` — provider string, sent as `phx-value-provider`
    * `:title` / `:description` — display copy
    * `:click_event` — event dispatched on select, or `nil` to render disabled
    * `:connected?` — whether the user already has an integration for it
  """
  @type provider_entry :: %{
          provider: String.t(),
          title: String.t(),
          description: String.t() | nil,
          click_event: String.t() | nil,
          connected?: boolean()
        }

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :target, :any, required: true
  attr :on_cancel, JS, default: %JS{}

  attr :groups, :list,
    default: [],
    doc: "list of %{label: String.t() | nil, providers: [provider_entry]}"

  attr :config_active, :boolean,
    default: false,
    doc: "when true the :config slot is rendered instead of the provider grid"

  attr :back_event, :string, default: nil, doc: "event that returns from config to the picker"
  slot :config

  @spec provider_picker_modal(map()) :: Phoenix.LiveView.Rendered.t()
  def provider_picker_modal(assigns) do
    ~H"""
    <div id={@id}>
      <TymeslotWeb.Components.CoreComponents.modal
        id={"#{@id}-modal"}
        show={@show}
        on_cancel={@on_cancel}
        size={:large}
      >
        <:header>
          <div class="flex items-center gap-3">
            <button
              :if={@config_active && @back_event}
              type="button"
              phx-click={@back_event}
              phx-target={@target}
              class="modal-icon-button modal-icon-button--sm modal-icon-button--neutral"
              aria-label={dgettext("dashboard_integrations", "Back to providers")}
            >
              <.icon name="hero-arrow-left" class="h-5 w-5" />
            </button>
            <div>
              <h2 class="text-token-lg font-semibold text-neutral-800 dark:text-neutral-100">
                {@title}
              </h2>
              <%!-- The modal renders its :header slot inside the .modal-title heading, so the
                   subtitle has to reset the heading's weight and tracking explicitly. --%>
              <p
                :if={@subtitle && !@config_active}
                class="mt-1 text-token-sm font-normal tracking-normal text-neutral-500 dark:text-twilight-indigo-200"
              >
                {@subtitle}
              </p>
            </div>
          </div>
        </:header>

        <div :if={@config_active}>
          {render_slot(@config)}
        </div>

        <div :if={!@config_active} class="space-y-6">
          <div :for={group <- @groups} :if={group.providers != []} class="space-y-3">
            <h3
              :if={group.label}
              class="text-token-2xs font-black uppercase tracking-widest text-neutral-400 dark:text-twilight-indigo-300"
            >
              {group.label}
            </h3>
            <div class="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <.provider_option
                :for={provider <- group.providers}
                provider={provider}
                target={@target}
              />
            </div>
          </div>
        </div>
      </TymeslotWeb.Components.CoreComponents.modal>
    </div>
    """
  end

  attr :provider, :map, required: true
  attr :target, :any, required: true

  defp provider_option(assigns) do
    ~H"""
    <button
      type="button"
      disabled={!@provider.click_event}
      phx-click={@provider.click_event}
      phx-value-provider={@provider.provider}
      phx-target={@target}
      class={[
        "group flex items-center gap-3 rounded-token-xl border-2 border-neutral-300 dark:border-twilight-indigo-800 bg-white dark:bg-twilight-indigo-950 p-3 text-left transition-all",
        (@provider.click_event &&
           "hover:border-primary-200 dark:hover:border-primary-700 hover:bg-primary-50/40 dark:hover:bg-primary-950/40") ||
          "opacity-60 cursor-not-allowed"
      ]}
    >
      <.provider_icon provider={@provider.provider} size="medium" class="shrink-0" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-1.5">
          <h4 class="truncate text-token-sm font-semibold text-neutral-800 dark:text-neutral-100">
            {@provider.title}
          </h4>
          <span
            :if={@provider.connected?}
            class="shrink-0 rounded-token-sm bg-primary-50 dark:bg-primary-950/40 px-1.5 py-0.5 text-token-2xs font-semibold text-primary-700 dark:text-primary-300"
          >
            {dgettext("dashboard_integrations", "Connected")}
          </span>
        </div>
        <p
          :if={@provider.description}
          class="line-clamp-2 text-token-xs leading-relaxed text-neutral-500 dark:text-twilight-indigo-300"
        >
          {@provider.description}
        </p>
      </div>
    </button>
    """
  end
end
