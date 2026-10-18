defmodule TymeslotWeb.Live.Dashboard.EmbedSettings.OptionsGrid do
  @moduledoc """
  Renders the embed options grid for the dashboard.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Live.Dashboard.EmbedSettings.Helpers

  @doc """
  Renders the embed options grid.
  """
  attr :selected_embed_type, :string, required: true
  attr :username, :string, required: true
  attr :base_url, :string, required: true
  attr :booking_url, :string, required: true
  attr :embed_layout, :string, default: "column"
  attr :embed_locale, :string, default: ""
  attr :embed_meeting, :string, default: ""
  attr :embed_background_mode, :string, default: "default"
  attr :embed_background_color, :string, default: "#ffffff"
  attr :meeting_type_options, :list, default: []
  attr :initial_height, :any, default: nil
  attr :max_width, :any, default: nil
  attr :myself, :any, required: true

  @spec options_grid(map()) :: Phoenix.LiveView.Rendered.t()
  def options_grid(assigns) do
    assigns = assign(assigns, :snippet_options, Helpers.snippet_options(assigns))

    ~H"""
    <.customise_panel
      embed_layout={@embed_layout}
      embed_locale={@embed_locale}
      embed_meeting={@embed_meeting}
      embed_background_mode={@embed_background_mode}
      embed_background_color={@embed_background_color}
      meeting_type_options={@meeting_type_options}
      initial_height={@initial_height}
      max_width={@max_width}
      myself={@myself}
    />

    <.subsection_header
      icon="hero-squares-2x2"
      title={dgettext("dashboard_embed", "Style Selection")}
      description={
        dgettext(
          "dashboard_embed",
          "Pick the style to try in the Live Preview. Each style has its own code below, so you can copy any of them."
        )
      }
      class="mb-4"
    />

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <.embed_option_card
        type="inline"
        selected={@selected_embed_type == "inline"}
        title={dgettext("dashboard_embed", "Inline Embed")}
        description={dgettext("dashboard_embed", "Embed directly into your webpage")}
        badge={dgettext("dashboard_embed", "Recommended")}
        badge_tone={:brand}
        myself={@myself}
      >
        <:preview>
          <div class="bg-white rounded shadow-sm p-4 dark:bg-twilight-indigo-900">
            <div class="flex items-center space-x-2 mb-3">
              <div class="w-3 h-3 rounded-token-full bg-red-400"></div>
              <div class="w-3 h-3 rounded-token-full bg-yellow-400"></div>
              <div class="w-3 h-3 rounded-token-full bg-green-400"></div>
            </div>
            <div class="space-y-2">
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-3/4"></div>
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-1/2"></div>
              <div class="mt-4 p-3 bg-linear-to-br from-primary-50 to-secondary-50 border-2 border-primary-200 rounded-token-lg dark:from-primary-950/40 dark:to-secondary-950/40 dark:border-primary-800">
                <div class="flex items-center space-x-2">
                  <.icon name="hero-calendar" class="w-4 h-4 text-primary-600 dark:text-primary-300" />
                  <div class="text-token-xs font-semibold text-primary-700 dark:text-primary-300">
                    {dgettext("dashboard_embed", "Your booking widget here")}
                  </div>
                </div>
              </div>
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-2/3"></div>
            </div>
          </div>
        </:preview>
        <:code>
          {Helpers.embed_code("inline", @snippet_options)}
        </:code>
        <:footer_info>
          {dgettext(
            "dashboard_embed",
            "Shows the booking calendar right on your page. Copy the code and paste it into your website's HTML."
          )}
        </:footer_info>
      </.embed_option_card>

      <%!-- Popup Modal option card --%>
      <.embed_option_card
        type="popup"
        selected={@selected_embed_type == "popup"}
        title={dgettext("dashboard_embed", "Popup Modal")}
        description={dgettext("dashboard_embed", "Trigger a modal overlay with a button")}
        badge={dgettext("dashboard_embed", "Popular")}
        badge_tone={:info}
        myself={@myself}
      >
        <:preview>
          <div class="bg-white rounded shadow-sm p-4 dark:bg-twilight-indigo-900">
            <div class="flex items-center space-x-2 mb-3">
              <div class="w-3 h-3 rounded-token-full bg-red-400"></div>
              <div class="w-3 h-3 rounded-token-full bg-yellow-400"></div>
              <div class="w-3 h-3 rounded-token-full bg-green-400"></div>
            </div>
            <div class="space-y-2">
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-3/4"></div>
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-1/2"></div>
              <div class="mt-4 flex justify-center">
                <div class="px-4 py-2 text-white text-token-xs font-bold rounded-token-lg shadow-lg bg-primary-600">
                  {dgettext("dashboard_embed", "Book a Meeting →")}
                </div>
              </div>
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-2/3"></div>
            </div>
          </div>
        </:preview>
        <:code>
          {Helpers.embed_code("popup", @snippet_options)}
        </:code>
        <:footer_info>
          {dgettext(
            "dashboard_embed",
            "Visitors click a button on your page and the booking calendar opens in an overlay."
          )}
        </:footer_info>
      </.embed_option_card>

      <.embed_option_card
        type="link"
        selected={@selected_embed_type == "link"}
        title={dgettext("dashboard_embed", "Direct Link")}
        description={dgettext("dashboard_embed", "Simple link to your booking page")}
        badge={dgettext("dashboard_embed", "Easiest")}
        badge_tone={:neutral}
        myself={@myself}
      >
        <:preview>
          <div class="bg-white rounded shadow-sm p-4 dark:bg-twilight-indigo-900">
            <div class="flex items-center space-x-2 mb-3">
              <div class="w-3 h-3 rounded-token-full bg-red-400"></div>
              <div class="w-3 h-3 rounded-token-full bg-yellow-400"></div>
              <div class="w-3 h-3 rounded-token-full bg-green-400"></div>
            </div>
            <div class="space-y-2">
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-3/4"></div>
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-1/2"></div>
              <div class="mt-4">
                <div class="text-token-xs text-primary-600 underline font-medium dark:text-primary-300">
                  {dgettext("dashboard_embed", "Schedule a meeting with me →")}
                </div>
              </div>
              <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-2/3"></div>
            </div>
          </div>
        </:preview>
        <:code>
          {Helpers.embed_code("link", @snippet_options)}
        </:code>
        <:footer_info>
          {dgettext(
            "dashboard_embed",
            "Share this link in emails, social media bios, or messages. No code needed."
          )}
        </:footer_info>
      </.embed_option_card>

      <.embed_option_card
        type="floating"
        selected={@selected_embed_type == "floating"}
        title={dgettext("dashboard_embed", "Floating Button")}
        description={dgettext("dashboard_embed", "Fixed button in corner of page")}
        badge={dgettext("dashboard_embed", "Expert")}
        badge_tone={:brand}
        myself={@myself}
      >
        <:preview>
          <div class="mb-0 bg-neutral-50 rounded-token-lg p-0 relative overflow-hidden dark:bg-twilight-indigo-950">
            <div class="bg-white rounded shadow-sm p-4 dark:bg-twilight-indigo-900">
              <div class="flex items-center space-x-2 mb-3">
                <div class="w-3 h-3 rounded-token-full bg-red-400"></div>
                <div class="w-3 h-3 rounded-token-full bg-yellow-400"></div>
                <div class="w-3 h-3 rounded-token-full bg-green-400"></div>
              </div>
              <div class="space-y-2">
                <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-3/4"></div>
                <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-1/2"></div>
                <div class="h-2 bg-neutral-200 rounded dark:bg-twilight-indigo-700 w-2/3"></div>
              </div>
            </div>
            <%!-- Floating button preview --%>
            <div class="absolute bottom-4 right-4">
              <div class="w-8 h-8 rounded-token-full shadow-lg flex items-center justify-center bg-primary-600">
                <.icon name="hero-calendar" class="w-4 h-4 text-white" />
              </div>
            </div>
          </div>
        </:preview>
        <:code>
          {Helpers.embed_code("floating", @snippet_options)}
        </:code>
        <:footer_info>
          {dgettext(
            "dashboard_embed",
            "A floating button stays visible as visitors scroll - like a chat widget, but for booking."
          )}
        </:footer_info>
      </.embed_option_card>
    </div>
    """
  end

  # Customisation panel — controls that drive every card's generated snippet:
  #   - layout: "column" (default — wide canvas, adapts to any container) or
  #     "default" (centred-with-cap, for standalone-style placements)
  #   - language: forced booking-page locale, or "Auto"
  #   - meeting type: pins the widget to one type (`data-meeting`), or the overview
  #   - background: the theme's own, transparent, or a picked colour (`data-background`)
  #   - initial-height: placeholder height (px) shown before the iframe auto-resizes
  #   - max-width: container max-width (px) for inline + popup + floating
  attr :embed_layout, :string, required: true
  attr :embed_locale, :string, required: true
  attr :embed_meeting, :string, required: true
  attr :embed_background_mode, :string, required: true
  attr :embed_background_color, :string, required: true
  attr :meeting_type_options, :list, required: true
  attr :initial_height, :any, required: true
  attr :max_width, :any, required: true
  attr :myself, :any, required: true

  defp customise_panel(assigns) do
    ~H"""
    <div class="mb-6 bg-white border-2 border-neutral-200 rounded-token-lg p-6 dark:bg-twilight-indigo-950 dark:border-twilight-indigo-800">
      <div class="flex items-center justify-between mb-4">
        <div>
          <h2 class="text-token-lg font-semibold text-neutral-900 dark:text-neutral-50">
            {dgettext("dashboard_embed", "Customise")}
          </h2>
          <p class="text-token-sm text-neutral-600 mt-1 dark:text-neutral-300">
            {dgettext(
              "dashboard_embed",
              "Updates every snippet below. Defaults work for most embeds - adjust when your site needs them."
            )}
          </p>
        </div>
      </div>

      <.form
        for={%{}}
        as={:customise}
        id="embed-customisation-form"
        phx-change="update_customisation"
        phx-target={@myself}
        class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"
      >
        <%!-- Meeting type --%>
        <.input
          type="select"
          id="embed-meeting"
          name="customise[meeting]"
          label={dgettext("dashboard_embed", "Meeting type")}
          options={[
            {dgettext("dashboard_embed", "All - the list of your meeting types"), ""}
            | @meeting_type_options
          ]}
          value={@embed_meeting}
        >
          <:description>
            {dgettext(
              "dashboard_embed",
              "Pick one to open its booking page directly. Without a choice, visitors see the meeting types marked \"Show in embedded widget\"."
            )}
          </:description>
        </.input>

        <%!-- Background --%>
        <.input
          type="select"
          id="embed-background-mode"
          name="customise[background_mode]"
          label={dgettext("dashboard_embed", "Background")}
          options={[
            {dgettext("dashboard_embed", "Theme default"), "default"},
            {dgettext("dashboard_embed", "Transparent - your page shows through"), "transparent"},
            {dgettext("dashboard_embed", "Custom colour"), "color"}
          ]}
          value={@embed_background_mode}
        >
          <:description>
            {dgettext(
              "dashboard_embed",
              "Replaces the booking page's background inside the widget only. Your public booking page keeps its own."
            )}
          </:description>
        </.input>

        <.input
          :if={@embed_background_mode == "color"}
          type="color"
          id="embed-background-color"
          name="customise[background_color]"
          label={dgettext("dashboard_embed", "Background colour")}
          value={@embed_background_color}
        />

        <%!-- Layout --%>
        <.input
          type="select"
          id="embed-layout"
          name="customise[layout]"
          label={dgettext("dashboard_embed", "Layout")}
          options={[
            {dgettext("dashboard_embed", "Column - wide canvas, fills the container (recommended)"),
             "column"},
            {dgettext("dashboard_embed", "Default - centred with a ~640px cap (standalone-style)"),
             "default"}
          ]}
          value={@embed_layout}
        >
          <:description>
            {dgettext(
              "dashboard_embed",
              "Column adapts to any container width. Default centres the booker - useful when you want a self-contained card inside a wide page."
            )}
          </:description>
        </.input>

        <%!-- Language --%>
        <.input
          type="select"
          id="embed-language"
          name="customise[locale]"
          label={dgettext("dashboard_embed", "Language")}
          options={[
            {dgettext("dashboard_embed", "Auto - visitor's browser"), ""}
            | Helpers.language_options()
          ]}
          value={@embed_locale}
        >
          <:description>
            {dgettext(
              "dashboard_embed",
              "Language for the booking page. Auto follows each visitor's browser preference."
            )}
          </:description>
        </.input>

        <%!-- No step: the server accepts any pixel value in range, and a
        stored width like 320 or 1024 is not a multiple of anything round.
        A step here would make the form unsubmittable for whoever already
        has one. --%>
        <%!-- Initial height --%>
        <.input
          type="number"
          id="embed-initial-height"
          name="customise[initial_height]"
          label={dgettext("dashboard_embed", "Initial height (px)")}
          min="200"
          max="2000"
          placeholder="400"
          value={@initial_height}
          phx-debounce="blur"
        >
          <:description>
            {dgettext(
              "dashboard_embed",
              "Placeholder shown before the iframe auto-resizes. Inline only."
            )}
          </:description>
        </.input>

        <%!-- Max width --%>
        <.input
          type="number"
          id="embed-max-width"
          name="customise[max_width]"
          label={dgettext("dashboard_embed", "Max width (px)")}
          min="200"
          max="2000"
          placeholder="1000"
          value={@max_width}
          phx-debounce="blur"
        >
          <:description>
            {dgettext("dashboard_embed", "Container max-width. Modal popup defaults to 1000px.")}
          </:description>
        </.input>
      </.form>
    </div>
    """
  end

  # Internal component for an individual embed option card.
  slot :preview, required: true
  slot :code, required: true
  slot :footer_info, required: true
  attr :type, :string, required: true
  attr :selected, :boolean, default: false
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :badge, :string, default: nil
  attr :badge_tone, :atom, default: :neutral
  attr :myself, :any, required: true

  defp embed_option_card(assigns) do
    ~H"""
    <div
      class={[
        "embed-option-card cursor-pointer group relative min-w-0 rounded-token-2xl border-2",
        if(@selected,
          do: "border-primary-500 shadow-md",
          else:
            "border-neutral-200 hover:border-primary-300 dark:border-twilight-indigo-800 dark:hover:border-primary-700"
        )
      ]}
      phx-click="select_embed_type"
      phx-value-type={@type}
      phx-target={@myself}
      data-selected={to_string(@selected)}
    >
      <div
        :if={@selected}
        class="absolute -top-3 -right-3 w-8 h-8 bg-primary-600 rounded-token-full flex items-center justify-center text-white shadow-lg z-10"
      >
        <.icon name="hero-check" class="w-5 h-5" />
      </div>
      <div class="p-6">
        <div class="flex items-start justify-between mb-4">
          <div>
            <h2 class="text-token-lg font-semibold text-neutral-900 dark:text-neutral-50">
              {@title}
            </h2>
            <p class="text-token-sm text-neutral-600 mt-1 dark:text-neutral-300">{@description}</p>
          </div>
          <.pill :if={@badge} tone={@badge_tone} size={:sm} uppercase>{@badge}</.pill>
        </div>

        <%!-- Preview --%>
        <div class="mb-4 bg-neutral-50 dark:bg-twilight-indigo-900/60 rounded-token-lg p-4 border-2 border-neutral-300 dark:border-twilight-indigo-800">
          {render_slot(@preview)}
        </div>

        <%!-- Code Snippet: lines keep their shape and scroll sideways inside
              the block rather than breaking mid-token. The Copy button sits
              above the block, so it never covers a line. --%>
        <div class="flex justify-end mb-2">
          <.action_button
            size={:sm}
            phx-click="copy_code"
            phx-value-type={@type}
            phx-target={@myself}
          >
            {dgettext("dashboard_embed", "Copy")}
          </.action_button>
        </div>
        <pre class="bg-neutral-100 text-neutral-800 border border-neutral-300 dark:bg-twilight-indigo-950 dark:text-neutral-100 dark:border-twilight-indigo-800 rounded-token-lg p-4 text-token-xs whitespace-pre overflow-x-auto"><code class="block"><%= @code |> render_slot() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary() |> String.split("\n") |> Enum.map_join("\n", &String.trim/1) |> String.trim() |> Phoenix.HTML.raw() %></code></pre>

        <div class="mt-4 flex items-start space-x-2 text-token-xs text-neutral-700 dark:text-neutral-200">
          <.icon name="hero-information-circle" class="w-4 h-4 text-primary-600 shrink-0 mt-0.5" />
          <span class="flex-1">{render_slot(@footer_info)}</span>
        </div>
      </div>
    </div>
    """
  end
end
