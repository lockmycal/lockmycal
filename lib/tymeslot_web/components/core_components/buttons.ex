defmodule TymeslotWeb.Components.CoreComponents.Buttons do
  @moduledoc """
  Button components extracted from CoreComponents.

  `action_button/1` and `action_link/1` share one look: the same variants and
  sizes, so a control that navigates and one that pushes an event sit side by
  side without drifting apart. `icon_button/1` is the square, icon-only
  sibling, and always carries an accessible label.
  """
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  # Application modules
  alias TymeslotWeb.Components.CoreComponents.Feedback, as: Feedback
  alias TymeslotWeb.Components.CoreComponents.Icons, as: Icons

  @variants [:primary, :secondary, :danger, :danger_soft, :outline, :ghost, :success, :on_dark]
  @sizes [:sm, :md, :lg]
  @icon_variants [:neutral, :danger, :warning]
  @icon_sizes [:sm, :md]

  # ========== BUTTONS ==========

  @doc """
  Renders an action button.

  ## Options
    * `:variant` - `:primary` (filled brand gradient, the one main action),
      `:secondary` (white, outlined), `:danger` (solid red; reserve it for the
      confirm button of a destructive confirmation), `:danger_soft` (red text and
      outline, no fill; a destructive action sitting beside a primary one),
      `:outline` (transparent, outlined), `:ghost` (no border or fill),
      `:success` (green gradient, an additive action) and `:on_dark` (white, for
      a button on a dark or brand-coloured surface). Defaults to `:primary`
    * `:size` - `:sm`, `:md` or `:lg`. Defaults to `:md`
    * `:icon` - A leading `hero-…` icon name
    * `:type` - Button type attribute. Defaults to "button"
    * `:disabled` - Whether the button is disabled. Defaults to false
    * `:class` - Additional CSS classes (layout only: width, margins)
  """
  attr :variant, :atom, default: :primary, values: @variants
  attr :size, :atom, default: :md, values: @sizes
  attr :icon, :string, default: nil, doc: "A leading `hero-…` icon name"
  attr :type, :string, default: "button"
  attr :form, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :class, :any, default: ""
  attr :rest, :global

  slot :inner_block, required: true

  @spec action_button(map()) :: Phoenix.LiveView.Rendered.t()
  def action_button(assigns) do
    ~H"""
    <button
      type={@type}
      form={@form}
      disabled={@disabled}
      class={action_classes(@variant, @size, @class)}
      {@rest}
    >
      <.leading_icon :if={@icon} name={@icon} size={@size} />
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc """
  Renders a link with the look of `action_button/1`.

  Takes exactly one of `navigate`, `patch` or `href`, as `Phoenix.Component.link/1`
  does, and the same `variant`, `size` and `icon` options as `action_button/1`.
  """
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :any, default: nil
  attr :replace, :boolean, default: false
  attr :method, :string, default: "get"
  attr :variant, :atom, default: :primary, values: @variants
  attr :size, :atom, default: :md, values: @sizes
  attr :icon, :string, default: nil, doc: "A leading `hero-…` icon name"
  attr :class, :any, default: ""

  attr :rest, :global, include: ~w(download hreflang referrerpolicy rel target type csrf_token)

  slot :inner_block, required: true

  @spec action_link(map()) :: Phoenix.LiveView.Rendered.t()
  def action_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      patch={@patch}
      href={@href}
      replace={@replace}
      method={@method}
      class={action_classes(@variant, @size, @class)}
      {@rest}
    >
      <.leading_icon :if={@icon} name={@icon} size={@size} />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a loading button with spinner.

  ## Options
    * `:loading` - Whether to show loading state
    * `:loading_text` - Text to show when loading
    * `:variant`, `:size`, `:icon` - As for `action_button/1`; the icon gives way
      to the spinner while loading
  """
  attr :loading, :boolean, default: false
  attr :loading_text, :string, default: nil
  attr :variant, :atom, default: :primary, values: @variants
  attr :size, :atom, default: :md, values: @sizes
  attr :icon, :string, default: nil, doc: "A leading `hero-…` icon name"
  attr :type, :string, default: "button"
  attr :form, :string, default: nil
  attr :class, :any, default: ""
  attr :disabled, :boolean, default: false
  attr :rest, :global

  slot :inner_block, required: true

  @spec loading_button(map()) :: Phoenix.LiveView.Rendered.t()
  def loading_button(assigns) do
    ~H"""
    <.action_button
      variant={@variant}
      size={@size}
      icon={if @loading, do: nil, else: @icon}
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

  @doc """
  Renders a square, icon-only button.

  `label` is required: it is the button's accessible name (`aria-label`) and,
  unless `tooltip` is given, its hover tooltip (`title`), since there is no
  visible text. On touch screens the hit area extends to at least 44px whatever
  the visual size.

  For a control that is unavailable but should say why, keep `label` naming
  the action ("Copy link"), put the reason in `tooltip`, and pass
  `aria-disabled="true"` rather than `disabled`, so it stays focusable and the
  reason stays reachable.

  ## Options
    * `:icon` - The `hero-…` icon name
    * `:label` - The accessible name, e.g. "Edit time off"
    * `:tooltip` - The hover tooltip, when it should differ from `label`
    * `:variant` - `:neutral` (bordered tile), `:danger` (quiet until hovered,
      then red) or `:warning` (amber tile). Defaults to `:neutral`
    * `:size` - `:sm` (32px) or `:md` (36px). Defaults to `:md`
  """
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :tooltip, :string, default: nil
  attr :variant, :atom, default: :neutral, values: @icon_variants
  attr :size, :atom, default: :md, values: @icon_sizes
  attr :type, :string, default: "button"
  attr :disabled, :boolean, default: false
  attr :class, :any, default: ""
  attr :rest, :global

  @spec icon_button(map()) :: Phoenix.LiveView.Rendered.t()
  def icon_button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      aria-label={@label}
      title={@tooltip || @label}
      class={["icon-button", "icon-button--#{@variant}", "icon-button--#{@size}", @class]}
      {@rest}
    >
      <Icons.icon name={@icon} class={icon_size_class(@size)} />
    </button>
    """
  end

  attr :name, :string, required: true
  attr :size, :atom, required: true

  defp leading_icon(assigns) do
    ~H"""
    <Icons.icon name={@name} class={"shrink-0 " <> icon_size_class(@size)} />
    """
  end

  @doc """
  The classes of an action button of the given variant and size, for an
  element that cannot be one of the components above: a `<label>` wrapping a
  file input. Add `aria-disabled="true"` to such an element when it is inert.
  """
  @spec button_classes(atom(), atom()) :: [String.t() | nil]
  def button_classes(variant, size \\ :md) when variant in @variants and size in @sizes do
    ["action-button", variant_class(variant), size_class(size)]
  end

  defp action_classes(variant, size, extra), do: button_classes(variant, size) ++ [extra]

  defp variant_class(:danger_soft), do: "action-button--danger-soft"
  defp variant_class(:on_dark), do: "action-button--on-dark"
  defp variant_class(variant), do: "action-button--#{variant}"

  # :md is the base `.action-button` size, so it needs no modifier class.
  defp size_class(:md), do: nil
  defp size_class(size), do: "action-button--#{size}"

  defp icon_size_class(:sm), do: "w-4 h-4"
  defp icon_size_class(size) when size in [:md, :lg], do: "w-5 h-5"
end
