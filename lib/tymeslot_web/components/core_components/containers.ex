defmodule TymeslotWeb.Components.CoreComponents.Containers do
  @moduledoc "Container and display components extracted from CoreComponents."
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Components.CoreComponents.Feedback
  alias TymeslotWeb.Components.CoreComponents.Icons
  alias TymeslotWeb.Components.Icons.IconComponents

  # ========== CARDS & CONTAINERS ==========

  @card_variants %{
    glass: nil,
    flat: "card-glass--flat",
    muted: "card-glass--muted"
  }

  @card_paddings %{
    none: "p-0",
    xs: "px-4 py-3",
    sm: "p-4",
    md: "p-6",
    lg: "p-6 sm:p-8"
  }

  @doc """
  Renders a dashboard card: the white surface every settings section and list
  sits on.

      <.card title="Booking limits" icon="hero-clock" description="Caps across every type">
        <:actions><.action_button size={:sm}>Reset</.action_button></:actions>
        ...
      </.card>

  * `variant`: `:glass` (the default, a lifted card on the page), `:flat` (the
    same surface without the shadow, for a card inside another card or a row
    in a list), `:muted` (a recessed tinted surface).
  * `padding`: `:none`, `:xs` (a compact list row), `:sm`, `:md` (the
    default) or `:lg`.
  * `interactive`: the whole card is clickable, so it shows a pointer and
    reacts to hover. Static cards do not.
  * `title` renders the card heading (an `<h2>` at the card-title scale) with
    an optional `icon` and `description`; the `:header` slot replaces it with
    custom content, and `:actions` sits at the header's end.

  `class` is for layout (margins, `space-y-*`, flex) and for state cues on the
  surface (a selected ring or border, an error border). The surface itself,
  its padding, shadow and hover, comes from `variant`, `padding` and
  `interactive`. The card's CSS sits in the components layer, so those
  utilities apply over it.
  """
  attr :variant, :atom, default: :glass, values: Map.keys(@card_variants)
  attr :padding, :atom, default: :md, values: Map.keys(@card_paddings)
  attr :interactive, :boolean, default: false
  attr :tag, :string, default: "div", values: ~w(div section article aside li)
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :icon, :string, default: nil, doc: "A `hero-…` icon beside the title"
  attr :class, :any, default: nil
  attr :title_id, :string, default: nil, doc: "The title heading's id, to label a control"
  attr :rest, :global

  slot :header, doc: "Custom header content, in place of `title`, `icon` and `description`"
  slot :actions, doc: "Controls at the end of the header row"
  slot :inner_block

  @spec card(map()) :: Phoenix.LiveView.Rendered.t()
  def card(assigns) do
    assigns =
      assign(assigns,
        variant_class: Map.fetch!(@card_variants, assigns.variant),
        padding_class: Map.fetch!(@card_paddings, assigns.padding),
        header?: assigns.title != nil or assigns.header != [] or assigns.actions != []
      )

    ~H"""
    <.dynamic_tag
      tag_name={@tag}
      class={[
        "card-glass",
        @variant_class,
        @padding_class,
        @interactive && "card-glass--interactive",
        @class
      ]}
      {@rest}
    >
      <div :if={@header?} class="mb-6 flex flex-wrap items-start justify-between gap-x-4 gap-y-3">
        <div class="min-w-0 flex-1">
          <%= if @header != [] do %>
            {render_slot(@header)}
          <% else %>
            <.subsection_header
              :if={@title}
              size={:lg}
              level={2}
              icon={@icon}
              id={@title_id}
              title={@title}
              description={@description}
            />
          <% end %>
        </div>
        <div :if={@actions != []} class="flex shrink-0 flex-wrap items-center gap-2">
          {render_slot(@actions)}
        </div>
      </div>
      {render_slot(@inner_block)}
    </.dynamic_tag>
    """
  end

  @subsection_sizes %{md: "text-token-base", lg: "text-token-lg"}

  @doc """
  Renders a small subsection header: an icon paired with a title and an optional
  description, for headings above a single block or group of blocks within a
  page (as opposed to `section_header/1`, which is the page's main heading).

  `level` sets the heading tag only, so the outline stays right wherever the
  header sits; `size` is `:md` for a subsection inside a card and `:lg` for a
  card's own title, which is what `<.card title>` renders. Give it an `id` when
  the heading is what labels a control (`aria-labelledby`).
  """
  attr :icon, :any,
    default: nil,
    doc: "A `hero-…` icon name (string) or a brand-mark atom (e.g. `:webhook`)"

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :size, :atom, default: :md, values: Map.keys(@subsection_sizes)
  attr :level, :integer, default: 3, values: [2, 3, 4]
  attr :id, :string, default: nil, doc: "The heading's id"

  attr :muted, :boolean,
    default: false,
    doc: "Dimmed treatment for a de-emphasized group (e.g. a paused/inactive section)."

  attr :count, :integer, default: nil, doc: "Optional count badge rendered after the title."

  attr :required, :boolean,
    default: false,
    doc: "Appends the red required-field asterisk (same as `<.input required>`) to the title."

  attr :class, :any, default: nil, doc: "Layout classes only"

  slot :badge,
    doc:
      "Optional trailing content rendered after the title (e.g. a locked-feature `ProBadge`); pushed to the row's far end via its own `ml-auto`."

  slot :actions, doc: "Controls at the end of the row"

  @spec subsection_header(map()) :: Phoenix.LiveView.Rendered.t()
  def subsection_header(assigns) do
    assigns = assign(assigns, :size_class, Map.fetch!(@subsection_sizes, assigns.size))

    ~H"""
    <div class={["flex items-center gap-2", @class]}>
      <Icons.icon
        :if={is_binary(@icon)}
        name={@icon}
        class={"w-5 h-5 #{if @muted, do: "text-neutral-300 dark:text-twilight-indigo-600", else: "text-primary-500"}"}
      />
      <IconComponents.icon
        :if={is_atom(@icon) and not is_nil(@icon)}
        name={@icon}
        class={"w-5 h-5 #{if @muted, do: "text-neutral-300 dark:text-twilight-indigo-600", else: "text-primary-500"}"}
      />
      <.subsection_title
        :if={!@description}
        level={@level}
        id={@id}
        size_class={@size_class}
        muted={@muted}
        required={@required}
        title={@title}
      />
      <div :if={@description} class="min-w-0">
        <.subsection_title
          level={@level}
          id={@id}
          size_class={@size_class}
          muted={@muted}
          required={@required}
          title={@title}
        />
        <p class="text-token-sm text-neutral-500 dark:text-neutral-400">
          {@description}
        </p>
      </div>
      <span
        :if={@count}
        class="bg-primary-100 text-primary-700 text-xs font-black px-3 py-1 rounded-full uppercase tracking-wider"
      >
        {@count}
      </span>
      {render_slot(@badge)}
      <div :if={@actions != []} class="ml-auto flex shrink-0 flex-wrap items-center gap-2">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  attr :level, :integer, required: true
  attr :id, :string, default: nil
  attr :size_class, :string, required: true
  attr :muted, :boolean, required: true
  attr :required, :boolean, required: true
  attr :title, :string, required: true

  defp subsection_title(assigns) do
    ~H"""
    <.dynamic_tag
      tag_name={"h#{@level}"}
      id={@id}
      class={[
        @size_class,
        "font-semibold",
        if(@muted,
          do: "text-neutral-400 dark:text-twilight-indigo-500",
          else: "text-neutral-800 dark:text-neutral-200"
        )
      ]}
    >
      {@title}<span :if={@required} class="text-red-500 ml-0.5">*</span>
    </.dynamic_tag>
    """
  end

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
  Renders a generic detail card with consistent styling. The title is an
  `<h2>` at the card-title scale.
  """
  attr :title, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block, required: true

  @spec detail_card(map()) :: Phoenix.LiveView.Rendered.t()
  def detail_card(assigns) do
    ~H"""
    <div class={["meeting-details-card", @class]}>
      <%= if @title do %>
        <h2 class="mb-4 text-token-lg font-semibold text-neutral-900 dark:text-neutral-50">
          {@title}
        </h2>
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
      "mx-auto flex items-center justify-center #{@size_classes} rounded-token-3xl mb-6 bg-linear-to-br from-primary-600 to-secondary-600 shadow-xl shadow-primary-500/20 border-4 border-white transform transition-transform hover:scale-110",
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
  attr :id, :string, default: nil, doc: "The heading's id"
  attr :title_class, :string, default: nil
  attr :class, :string, default: ""
  slot :inner_block
  slot :actions, doc: "Controls at the end of the row"

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

      <.dynamic_tag tag_name={"h#{@level}"} id={@id} class={@computed_title_class}>
        <%= if @title do %>
          {@title}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </.dynamic_tag>

      <%= if @count do %>
        <span class="ml-4 bg-primary-100 text-primary-700 text-xs font-black px-3 py-1 rounded-full uppercase tracking-wider">
          {@count}
        </span>
      <% end %>

      <%!-- Always rendered, so a screen reader announces "Saving changes..." when it appears. --%>
      <div role="status" class="ml-auto">
        <div
          :if={@saving}
          class="bg-emerald-50 text-emerald-700 px-4 py-2 rounded-full font-black text-xs uppercase tracking-wider border-2 border-emerald-100 flex items-center"
        >
          <Feedback.spinner class="h-4 w-4 mr-2" />
          {dgettext("common", "Saving changes...")}
        </div>
      </div>

      <div :if={@actions != []} class="flex flex-wrap items-center gap-2 sm:gap-3">
        {render_slot(@actions)}
      </div>
    </div>

    <p :if={@icon && @subtitle} class="text-neutral-600 dark:text-neutral-400 mb-6">
      {@subtitle}
    </p>

    <.dynamic_tag
      :if={!@icon and @actions == []}
      tag_name={"h#{@level}"}
      id={@id}
      class={[@computed_title_class, "mb-2", @class]}
    >
      <%= if @title do %>
        {@title}
      <% else %>
        {render_slot(@inner_block)}
      <% end %>
    </.dynamic_tag>

    <div
      :if={!@icon and @actions != []}
      class={["mb-2 flex flex-wrap items-center justify-between gap-x-4 gap-y-3", @class]}
    >
      <.dynamic_tag tag_name={"h#{@level}"} id={@id} class={@computed_title_class}>
        <%= if @title do %>
          {@title}
        <% else %>
          {render_slot(@inner_block)}
        <% end %>
      </.dynamic_tag>
      <div class="flex flex-wrap items-center gap-2 sm:gap-3">
        {render_slot(@actions)}
      </div>
    </div>

    <p :if={!@icon && @subtitle} class="text-neutral-600 dark:text-neutral-400 mb-6">
      {@subtitle}
    </p>
    """
  end

  @detail_tiles %{
    brand:
      "bg-primary-50 border-primary-100 text-primary-600 dark:bg-primary-950/30 dark:border-primary-800 dark:text-primary-400",
    info:
      "bg-blue-50 border-blue-100 text-blue-600 dark:bg-blue-950/30 dark:border-blue-800 dark:text-blue-400",
    danger:
      "bg-red-50 border-red-100 text-red-500 dark:bg-red-950/30 dark:border-red-800 dark:text-red-400"
  }

  @doc """
  One line of details: an icon beside an optional label, over the value in the
  inner block.

      <.detail_line icon="hero-clock" label="Time">2:30 PM – 3:00 PM</.detail_line>

  * `:default`: a brand icon, an uppercase label and a bold value. Detail modals.
  * `:compact`: a small muted icon beside free content (text, inputs, pickers),
    with a quiet label when given. Rows of an editable form.
  * `:tile`: the icon in a square tinted by `tone`, for cards with room to spare.
    `tone` applies to this variant only.
  """
  attr :icon, :string, required: true
  attr :label, :string, default: nil
  attr :variant, :atom, default: :default, values: [:default, :compact, :tile]

  attr :tone, :atom,
    default: :brand,
    values: Map.keys(@detail_tiles),
    doc: "The tile's tint; `:tile` only, the other variants ignore it"

  attr :class, :any, default: nil, doc: "Layout classes only"
  attr :rest, :global
  slot :inner_block, required: true

  @spec detail_line(map()) :: Phoenix.LiveView.Rendered.t()
  def detail_line(%{variant: :tile} = assigns) do
    assigns = assign(assigns, :tile_class, Map.fetch!(@detail_tiles, assigns.tone))

    ~H"""
    <div class={["flex items-center gap-4", @class]} {@rest}>
      <div class={[
        "w-12 h-12 shrink-0 rounded-token-2xl border shadow-sm flex items-center justify-center",
        @tile_class
      ]}>
        <Icons.icon name={@icon} class="w-6 h-6" />
      </div>
      <div class="min-w-0">
        <p
          :if={@label}
          class="text-token-xs font-black text-neutral-400 uppercase tracking-widest mb-0.5 dark:text-twilight-indigo-300"
        >
          {@label}
        </p>
        <div class="text-neutral-700 font-bold break-words dark:text-neutral-200">
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  def detail_line(%{variant: :compact} = assigns) do
    ~H"""
    <div class={["flex items-start gap-3", @class]} {@rest}>
      <Icons.icon
        name={@icon}
        class="w-4 h-4 text-neutral-400 mt-0.5 shrink-0 dark:text-twilight-indigo-300"
      />
      <div class="min-w-0 flex-1">
        <p
          :if={@label}
          class="text-token-xs font-medium text-neutral-400 mb-1.5 dark:text-twilight-indigo-300"
        >
          {@label}
        </p>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  def detail_line(assigns) do
    ~H"""
    <div class={["flex items-start gap-3", @class]} {@rest}>
      <Icons.icon name={@icon} class="w-5 h-5 text-primary-500 shrink-0 mt-0.5" />
      <div class="min-w-0 flex-1">
        <p
          :if={@label}
          class="text-token-xs font-black uppercase tracking-widest text-neutral-400 dark:text-twilight-indigo-300"
        >
          {@label}
        </p>
        <div class="mt-0.5 text-neutral-800 font-bold break-words dark:text-neutral-100">
          {render_slot(@inner_block)}
        </div>
      </div>
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
          "bg-green-50 border-green-200 text-green-800 dark:bg-green-950/40 dark:border-green-800 dark:text-green-300"

        :warning ->
          "bg-amber-50 border-amber-200 text-amber-800 dark:bg-amber-950/40 dark:border-amber-800 dark:text-amber-300"

        :error ->
          "bg-red-50 border-red-200 text-red-800 dark:bg-red-950/40 dark:border-red-800 dark:text-red-300"

        :info ->
          "bg-blue-50 border-blue-200 text-blue-800 dark:bg-blue-950/40 dark:border-blue-800 dark:text-blue-300"

        _other ->
          "bg-neutral-50 border-neutral-200 text-neutral-800 dark:bg-twilight-indigo-900 dark:border-twilight-indigo-700 dark:text-neutral-200"
      end

    assigns = assign(assigns, :classes, classes)

    ~H"""
    <div class={["rounded-token-2xl p-6 mb-8 border-2", @classes, @class]}>
      <div class="font-medium">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end
end
