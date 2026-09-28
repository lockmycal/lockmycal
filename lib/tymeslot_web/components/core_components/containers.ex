defmodule TymeslotWeb.Components.CoreComponents.Containers do
  @moduledoc "Container and display components extracted from CoreComponents."
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.CoreComponents.Feedback
  alias TymeslotWeb.Components.CoreComponents.Icons
  alias TymeslotWeb.Components.Icons.IconComponents

  # ========== CARDS & CONTAINERS ==========

  @doc """
  Renders a glass-morphism card container.
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec glass_morphism_card(map()) :: Phoenix.LiveView.Rendered.t()
  def glass_morphism_card(assigns) do
    ~H"""
    <div class={["glass-morphism-card", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a generic detail card with consistent styling.
  """
  attr :title, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec detail_card(map()) :: Phoenix.LiveView.Rendered.t()
  def detail_card(assigns) do
    ~H"""
    <div class={["meeting-details-card", @class]}>
      <%= if @title do %>
        <h3 class="text-xl font-black mb-4 text-neutral-900 dark:text-neutral-50 tracking-tight">
          {@title}
        </h3>
      <% end %>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders an icon badge with gradient background.

  Accepts either a `hero-…` icon name via the `icon` attribute, rendered
  through `<.icon>`, or raw SVG child markup (e.g. `<path>`) via the default
  slot, drawn inside the badge's own `<svg>` wrapper. `<.icon>` renders a
  complete `<svg>` of its own, so it must never be passed as slot content —
  that nests one `<svg>` inside another.
  """
  attr :size, :atom, default: :medium, values: [:small, :medium, :large]
  attr :icon, :string, default: nil, doc: "A `hero-…` icon name, rendered via `<.icon>`"
  attr :class, :string, default: ""
  slot :inner_block, doc: "Raw SVG children (e.g. `<path>`), used when `icon` is not given"

  @spec icon_badge(map()) :: Phoenix.LiveView.Rendered.t()
  def icon_badge(assigns) do
    size_classes =
      case assigns.size do
        :small -> "h-12 w-12"
        :large -> "h-24 w-24"
        _other -> "h-16 w-16"
      end

    icon_size =
      case assigns.size do
        :small -> "h-6 w-6"
        :large -> "h-12 w-12"
        _other -> "h-8 w-8"
      end

    assigns = assigns |> assign(:size_classes, size_classes) |> assign(:icon_size, icon_size)

    ~H"""
    <div class={[
      "mx-auto flex items-center justify-center #{@size_classes} rounded-3xl mb-6 bg-linear-to-br from-primary-600 to-secondary-600 shadow-xl shadow-primary-500/20 border-4 border-white transform transition-transform hover:scale-110",
      @class
    ]}>
      <Icons.icon :if={@icon} name={@icon} class={"#{@icon_size} text-white"} />
      <svg
        :if={!@icon}
        class={"#{@icon_size} text-white"}
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        stroke-width="2.5"
      >
        {render_slot(@inner_block)}
      </svg>
    </div>
    """
  end

  @doc """
  Renders a section header with consistent styling. Supports optional icon, count badge, and saving indicator.
  """
  attr :icon, :any,
    default: nil,
    doc: "A `hero-…` icon name (string) or a brand-mark atom (e.g. `:webhook`)"

  attr :title, :string, default: nil
  attr :subtitle, :string, default: nil
  attr :count, :integer, default: nil
  attr :saving, :boolean, default: false
  attr :level, :integer, default: 1
  attr :title_class, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block

  @spec section_header(map()) :: Phoenix.LiveView.Rendered.t()
  def section_header(assigns) do
    size_class =
      case assigns.level do
        1 -> "text-4xl"
        2 -> "text-3xl"
        3 -> "text-2xl"
        _other -> "text-xl"
      end

    computed_title_class =
      assigns.title_class ||
        "#{size_class} font-black text-neutral-900 dark:text-neutral-100 tracking-tight"

    assigns =
      assigns
      |> assign(:size_class, size_class)
      |> assign(:computed_title_class, computed_title_class)

    ~H"""
    <div :if={@icon} class={["flex items-center mb-4", @class]}>
      <div class="w-14 h-14 bg-white dark:bg-twilight-indigo-900 rounded-2xl flex items-center justify-center mr-5 shadow-sm border border-neutral-300 dark:border-twilight-indigo-700 shrink-0">
        <%!-- Hero icons arrive as `hero-…` strings; the few brand marks with no
             Heroicon equivalent (e.g. `:webhook`) arrive as atoms. --%>
        <Icons.icon :if={is_binary(@icon)} name={@icon} class="w-8 h-8 text-primary-600" />
        <IconComponents.icon :if={is_atom(@icon)} name={@icon} class="w-8 h-8 text-primary-600" />
      </div>

      <h1 class={@computed_title_class}>
        <%= if @title do %>
          {@title}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </h1>

      <%= if @count do %>
        <span class="ml-4 bg-primary-100 text-primary-700 text-xs font-black px-3 py-1 rounded-full uppercase tracking-wider">
          {@count}
        </span>
      <% end %>

      <%= if @saving do %>
        <div class="ml-auto bg-emerald-50 text-emerald-700 px-4 py-2 rounded-full font-black text-xs uppercase tracking-wider border-2 border-emerald-100 flex items-center">
          <Feedback.spinner class="h-4 w-4 mr-2" />
          {dgettext("common", "Saving changes...")}
        </div>
      <% end %>
    </div>

    <p :if={@icon && @subtitle} class="text-neutral-600 dark:text-neutral-400 mb-6">
      {@subtitle}
    </p>

    <h1 :if={!@icon} class={[@computed_title_class, "mb-2", @class]}>
      <%= if @title do %>
        {@title}
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </h1>

    <p :if={!@icon && @subtitle} class="text-neutral-600 dark:text-neutral-400 mb-6">
      {@subtitle}
    </p>
    """
  end

  @doc """
  Renders a small subsection header: an icon paired with a title, for headings above
  a single block or group of blocks within a page (as opposed to `section_header/1`,
  which is the page's main heading).
  """
  attr :icon, :any,
    required: true,
    doc: "A `hero-…` icon name (string) or a brand-mark atom (e.g. `:webhook`)"

  attr :title, :string, required: true

  attr :muted, :boolean,
    default: false,
    doc: "Dimmed treatment for a de-emphasized group (e.g. a paused/inactive section)."

  attr :count, :integer, default: nil, doc: "Optional count badge rendered after the title."

  attr :required, :boolean,
    default: false,
    doc: "Appends the red required-field asterisk (same as `<.input required>`) to the title."

  attr :class, :string, default: ""

  slot :badge,
    doc:
      "Optional trailing content rendered after the title (e.g. a locked-feature `ProBadge`); pushed to the row's far end via its own `ml-auto`."

  @spec subsection_header(map()) :: Phoenix.LiveView.Rendered.t()
  def subsection_header(assigns) do
    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <Icons.icon
        :if={is_binary(@icon)}
        name={@icon}
        class={"w-5 h-5 #{if @muted, do: "text-neutral-300 dark:text-twilight-indigo-600", else: "text-primary-500"}"}
      />
      <IconComponents.icon
        :if={is_atom(@icon)}
        name={@icon}
        class={"w-5 h-5 #{if @muted, do: "text-neutral-300 dark:text-twilight-indigo-600", else: "text-primary-500"}"}
      />
      <h3 class={[
        "text-token-base font-semibold",
        if(@muted,
          do: "text-neutral-400 dark:text-twilight-indigo-500",
          else: "text-neutral-800 dark:text-neutral-200"
        )
      ]}>
        {@title}<span :if={@required} class="text-red-500 ml-0.5">*</span>
      </h3>
      <span
        :if={@count}
        class="bg-primary-100 text-primary-700 text-xs font-black px-3 py-1 rounded-full uppercase tracking-wider"
      >
        {@count}
      </span>
      {render_slot(@badge)}
    </div>
    """
  end

  @doc """
  Renders an info/alert box.
  """
  attr :variant, :atom, default: :info, values: [:info, :success, :warning, :error]
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec info_box(map()) :: Phoenix.LiveView.Rendered.t()
  def info_box(assigns) do
    classes =
      case assigns.variant do
        :success ->
          "bg-emerald-50 dark:bg-emerald-950/40 border-emerald-200 dark:border-emerald-800 text-emerald-800 dark:text-emerald-200"

        :warning ->
          "bg-amber-50 dark:bg-amber-950/40 border-amber-200 dark:border-amber-800 text-amber-800 dark:text-amber-200"

        :error ->
          "bg-red-50 dark:bg-red-950/40 border-red-200 dark:border-red-800 text-red-800 dark:text-red-200"

        :info ->
          "bg-sky-50 dark:bg-sky-950/40 border-sky-200 dark:border-sky-800 text-sky-800 dark:text-sky-200"

        _other ->
          "bg-neutral-50 dark:bg-twilight-indigo-900 border-neutral-300 dark:border-twilight-indigo-700 text-neutral-800 dark:text-neutral-200"
      end

    assigns = assign(assigns, :classes, classes)

    ~H"""
    <div class={["rounded-2xl p-6 mb-8 border-2", @classes, @class]}>
      <p class="font-medium">
        {render_slot(@inner_block)}
      </p>
    </div>
    """
  end
end
