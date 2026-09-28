defmodule TymeslotWeb.Components.CoreComponents.Buttons do
  @moduledoc "Button components extracted from CoreComponents."
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  # Application modules
  alias TymeslotWeb.Components.CoreComponents.Feedback, as: Feedback

  # ========== BUTTONS ==========

  @doc """
  Renders an action button with gradient styling.

  ## Options
    * `:variant` - Button variant (:primary, :secondary, :danger, :outline). Defaults to :primary
    * `:type` - Button type attribute. Defaults to "button"
    * `:disabled` - Whether the button is disabled. Defaults to false
    * `:class` - Additional CSS classes
  """
  attr :variant, :atom,
    default: :primary,
    values: [:primary, :secondary, :danger, :outline],
    doc:
      "controls visual style: :primary (filled), :secondary (outlined), :danger (red), :outline (ghost/text-only)"

  attr :type, :string, default: "button"
  attr :form, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :class, :string, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  @spec action_button(map()) :: Phoenix.LiveView.Rendered.t()
  def action_button(assigns) do
    ~H"""
    <button
      type={@type}
      form={@form}
      disabled={@disabled}
      class={["action-button", "action-button--#{@variant}", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a loading button with spinner.

  ## Options
    * `:loading` - Whether to show loading state
    * `:loading_text` - Text to show when loading
    * `:variant` - Button variant (passed to action_button)
  """
  attr :loading, :boolean, default: false
  attr :loading_text, :string, default: nil
  attr :variant, :atom, default: :primary
  attr :type, :string, default: "button"
  attr :form, :string, default: nil
  attr :class, :string, default: ""
  attr :disabled, :boolean, default: false
  attr :rest, :global

  slot :inner_block, required: true

  @spec loading_button(map()) :: Phoenix.LiveView.Rendered.t()
  def loading_button(assigns) do
    ~H"""
    <.action_button
      variant={@variant}
      type={@type}
      form={@form}
      disabled={@loading or @disabled}
      class={@class}
      {@rest}
    >
      <%= if @loading do %>
        <Feedback.spinner />
        <span>{@loading_text || dgettext("common", "Processing...")}</span>
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </.action_button>
    """
  end

  @doc """
  Renders the two-pill Enabled/Disabled toggle used on the admin settings
  page, for reuse anywhere else a boolean setting wants the same look. The
  currently-active pill renders disabled (it's already selected); clicking
  the other one fires `click_event` with `phx-value-state="true"`/`"false"`.
  """
  attr :active, :boolean, required: true, doc: "current value — true shows Enabled as active"
  attr :click_event, :string, required: true
  attr :target, :any, default: nil
  attr :aria_label, :string, required: true

  attr :disabled, :boolean,
    default: false,
    doc:
      "force both pills non-interactive regardless of :active, e.g. when a prerequisite (like a Stripe connection) isn't met"

  @spec enabled_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def enabled_toggle(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={@aria_label}
      class={[
        "inline-flex p-1 bg-white dark:bg-twilight-indigo-900 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1 shrink-0",
        @disabled && "opacity-60"
      ]}
    >
      <.enabled_toggle_tag
        active={@active}
        label={dgettext("dashboard_common", "Enabled")}
        state="true"
        click_event={@click_event}
        target={@target}
        disabled={@disabled}
      />
      <.enabled_toggle_tag
        active={!@active}
        label={dgettext("dashboard_common", "Disabled")}
        state="false"
        click_event={@click_event}
        target={@target}
        disabled={@disabled}
      />
    </div>
    """
  end

  attr :active, :boolean, required: true
  attr :label, :string, required: true
  attr :state, :string, required: true
  attr :click_event, :string, required: true
  attr :target, :any, default: nil
  attr :disabled, :boolean, default: false

  defp enabled_toggle_tag(assigns) do
    ~H"""
    <button
      type="button"
      phx-target={@target}
      phx-click={@click_event}
      phx-value-state={@state}
      disabled={@active or @disabled}
      aria-pressed={@active}
      class={[
        "px-3 py-1.5 rounded-token-lg text-token-xs font-black uppercase tracking-wider transition-all",
        if(@active,
          do: "bg-primary-600 text-white cursor-default",
          else:
            "text-neutral-500 dark:text-neutral-400 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 hover:text-neutral-900 dark:hover:text-neutral-100 cursor-pointer"
        ),
        @disabled && "cursor-not-allowed"
      ]}
    >
      {@label}
    </button>
    """
  end

  @doc """
  Same pill-toggle look as `enabled_toggle`, for a two-option setting whose
  values aren't literally "Enabled"/"Disabled" (e.g. a 12h/24h choice).
  Clicking the inactive pill fires `click_event` with `phx-value-option`
  set to that option's value.
  """
  attr :options, :list,
    required: true,
    doc:
      "two or more `{value, label}` string pairs, in display order — or " <>
        "`{value, label, badge}` to show a small pill after that option's " <>
        "label (e.g. a yearly option's \"Save 17%\")"

  attr :active_value, :string, required: true
  attr :click_event, :string, required: true
  attr :target, :any, default: nil
  attr :aria_label, :string, required: true

  @spec option_toggle(map()) :: Phoenix.LiveView.Rendered.t()
  def option_toggle(assigns) do
    ~H"""
    <div
      role="group"
      aria-label={@aria_label}
      class="inline-flex p-1 bg-white dark:bg-twilight-indigo-900 border-2 border-neutral-300 dark:border-twilight-indigo-700 rounded-token-xl shadow-sm gap-1 shrink-0"
    >
      <.option_toggle_tag
        :for={option <- @options}
        active={elem(option, 0) == @active_value}
        label={elem(option, 1)}
        badge={if tuple_size(option) == 3, do: elem(option, 2)}
        value={elem(option, 0)}
        click_event={@click_event}
        target={@target}
      />
    </div>
    """
  end

  attr :active, :boolean, required: true
  attr :label, :string, required: true
  attr :badge, :string, default: nil
  attr :value, :string, required: true
  attr :click_event, :string, required: true
  attr :target, :any, default: nil

  defp option_toggle_tag(assigns) do
    ~H"""
    <button
      type="button"
      phx-target={@target}
      phx-click={@click_event}
      phx-value-option={@value}
      disabled={@active}
      aria-pressed={@active}
      class={[
        "flex items-center gap-1.5 px-3 py-1.5 rounded-token-lg text-token-xs font-black uppercase tracking-wider transition-all",
        if(@active,
          do: "bg-primary-600 text-white cursor-default",
          else:
            "text-neutral-500 dark:text-neutral-400 hover:bg-neutral-50 dark:hover:bg-twilight-indigo-800 hover:text-neutral-900 dark:hover:text-neutral-100 cursor-pointer"
        )
      ]}
    >
      {@label}
      <span
        :if={@badge}
        class={[
          "rounded-token-full px-1.5 py-0.5 text-[10px] normal-case tracking-normal",
          if(@active,
            do: "bg-white/20 text-white",
            else: "bg-primary-50 dark:bg-primary-950/40 text-primary-700 dark:text-primary-300"
          )
        ]}
      >
        {@badge}
      </span>
    </button>
    """
  end
end
