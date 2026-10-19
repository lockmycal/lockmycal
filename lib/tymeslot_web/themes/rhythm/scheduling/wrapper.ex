defmodule TymeslotWeb.Themes.Rhythm.Scheduling.Wrapper do
  @moduledoc """
  The Rhythm theme's wrapper: its video, gradient, colour or image
  background, and its page grid (`.booker-page`, sized to content in an
  embed by its `iframe.css`) holding the content area and the theme
  extensions as its footer row, inside the shared `ThemeShell`.
  """
  use Phoenix.Component

  alias Tymeslot.Locales
  alias Tymeslot.Themes.Catalog
  alias TymeslotWeb.Themes.Shared.Components.ThemeShell
  alias TymeslotWeb.Themes.Shared.ThemeStyle

  import TymeslotWeb.Components.BackgroundMotionToggle,
    only: [background_motion_toggle: 1]

  import TymeslotWeb.Themes.Shared.Customization.Helpers, only: [prepare_wrapper_assigns: 1]
  import TymeslotWeb.Themes.Shared.VideoSources, only: [video_sources: 1]
  import TymeslotWeb.Components.PublicTopBar
  import TymeslotWeb.Components.PublicFooter
  import TymeslotWeb.Themes.Shared.Components.PreviewNotice, only: [banner: 1]
  import TymeslotWeb.Themes.Shared.Components.EmbedBackground, only: [embed_background: 1]

  attr :theme_tokens, :any, default: nil
  attr :locale, :string, default: nil
  attr :current_state, :atom, default: nil
  attr :language_dropdown_open, :boolean, default: nil
  attr :organizer_user_id, :integer, default: nil
  attr :should_show_branding, :boolean, default: false
  attr :show_language_switcher, :boolean, default: nil
  attr :owner_preview, :boolean, default: false
  attr :demo_mode, :boolean, doc: "handed to the theme extensions only when given"
  attr :current_user, :map, default: nil
  attr :embedded, :boolean, default: false
  attr :username_context, :string, default: nil
  attr :brand_logo_url, :string, default: nil
  attr :embed_background, :string, default: nil
  slot :inner_block, required: true

  @doc """
  Renders the Rhythm theme wrapper with custom styles and background.
  """
  @spec rhythm_wrapper(map()) :: Phoenix.LiveView.Rendered.t()
  def rhythm_wrapper(assigns) do
    assigns = assigns |> prepare_wrapper_assigns() |> assign(:theme_id, theme_id())

    ~H"""
    <ThemeShell.theme_shell
      class="rhythm-theme-wrapper"
      locale={@locale}
      theme_tokens={@theme_tokens}
    >
      <:background>
        <%= cond do %>
          <% @has_video_background -> %>
            <div class="video-background-container" id="rhythm-video-container" phx-hook="RhythmVideo">
              <video
                id="rhythm-background-video-1"
                autoplay
                muted
                loop
                playsinline
                poster={@background.poster}
                class="video-background-video active"
                preload="metadata"
              >
                <.video_sources sources={@background.sources} />
              </video>
              <video
                id="rhythm-background-video-2"
                muted
                loop
                playsinline
                poster={@background.poster}
                class="video-background-video inactive"
                preload="none"
              >
                <.video_sources sources={@background.sources} />
              </video>
            </div>
            <.background_motion_toggle />
          <% @background -> %>
            <div class="video-background-container" style={ThemeStyle.inline_background(@background)}>
            </div>
          <% true -> %>
            <div class="video-background-container"></div>
        <% end %>
      </:background>
      <.embed_background :if={@embedded} value={@embed_background} />
      <div class="booker-page video-background-theme theme-grid">
        <div class="content-area">
          <%!-- LockMyCal: the shared public top bar (logo, language, sign-in)
               instead of the shell's bare language switcher. --%>
          <.banner owner_preview={@owner_preview} />
          <.public_top_bar
            :if={@locale && @language_dropdown_open != nil && @show_language_switcher}
            locale={@locale}
            locales={Locales.supported()}
            dropdown_open={@language_dropdown_open}
            theme="rhythm"
            current_user={@current_user}
            embedded={@embedded}
            username={@username_context}
            brand_logo_url={@brand_logo_url}
          />
          {render_slot(@inner_block)}
        </div>

        <.public_footer embedded={@embedded} />
        <ThemeShell.extensions
          theme_id={@theme_id}
          organizer_user_id={@organizer_user_id}
          should_show_branding={@should_show_branding}
          {Map.take(assigns, [:demo_mode])}
        />
      </div>
    </ThemeShell.theme_shell>
    """
  end

  defp theme_id do
    {:ok, id} = Catalog.key_to_id(:rhythm)
    id
  end
end
