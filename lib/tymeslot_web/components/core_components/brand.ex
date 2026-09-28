defmodule TymeslotWeb.Components.CoreComponents.Brand do
  @moduledoc "Brand-related components (logos, marks) extracted from CoreComponents."
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config

  @doc """
  Renders the Tymeslot logo.

  ## Attributes
    * `mode` - Either :full (logo + text) or :icon (logo only). Defaults to :full.
    * `variant` - :light (dark wordmark, for light backgrounds), :dark (light
      wordmark, for dark/glass backgrounds), or :auto (renders both, toggled
      purely via CSS `dark:` — for a surface like the dashboard topbar that
      switches between the two at runtime under a `.dark` class, where a
      single server-picked variant can't react to the client-side toggle).
      Only affects `mode: :full` — the icon-only mark has no baked-in text
      and reads fine on either. Defaults to :light.
    * `class` - Additional CSS classes for the container.
    * `img_class` - Additional CSS classes for the image element.
  """
  attr :mode, :atom, default: :full, values: [:full, :icon]
  attr :variant, :atom, default: :light, values: [:light, :dark, :auto]
  attr :class, :string, default: nil
  attr :img_class, :string, default: "h-10"

  @spec logo(map()) :: Phoenix.LiveView.Rendered.t()
  def logo(assigns) do
    ~H"""
    <div class={["flex items-center", @class]}>
      <%= if @mode == :full do %>
        <%= if @variant == :auto do %>
          <img
            src={full_logo_src(:light)}
            alt={Config.app_name()}
            width="620"
            height="200"
            class={[@img_class, "w-auto dark:hidden"]}
          />
          <img
            src={full_logo_src(:dark)}
            alt={Config.app_name()}
            width="620"
            height="200"
            class={[@img_class, "w-auto hidden dark:block"]}
          />
        <% else %>
          <img
            src={full_logo_src(@variant)}
            alt={Config.app_name()}
            width="620"
            height="200"
            class={[@img_class, "w-auto"]}
          />
        <% end %>
      <% else %>
        <img
          src="/images/brand/logo.svg"
          alt={dgettext("common", "%{app_name} logo", app_name: Config.app_name())}
          width="200"
          height="200"
          class={[@img_class, "w-auto"]}
        />
      <% end %>
    </div>
    """
  end

  defp full_logo_src(:dark), do: "/images/brand/logo-with-text-dark.svg"
  defp full_logo_src(:light), do: "/images/brand/logo-with-text.svg"
end
