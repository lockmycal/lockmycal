defmodule TymeslotWeb.Themes.Shared.Customization.Helpers do
  @moduledoc """
  Helper functions for applying theme customizations to booking pages.
  """
  use Phoenix.Component

  alias Tymeslot.Demo
  alias Tymeslot.Profiles.BrandLogo
  alias Tymeslot.ThemeCustomizations
  alias Tymeslot.ThemeCustomizations.Tokens
  alias Tymeslot.ThemeCustomizations.Validation
  alias TymeslotWeb.Themes.Shared.Journey.Navigators.Reveal

  @doc """
  Assigns `:theme_tokens` to a socket: the `%Tokens{}` the theme's spec builds
  from the organiser's customisation, or from the theme's defaults when the
  organiser has none, plus the page view's `:theme_overrides` (an embed's
  `?primary-color=`) when the context assigned any. Also assigns
  `:brand_logo_url`, the organiser's own logo for the top bar (`BrandLogo`).
  """
  @spec assign_theme_customization(Phoenix.LiveView.Socket.t(), map(), String.t()) ::
          Phoenix.LiveView.Socket.t()
  def assign_theme_customization(socket, profile, theme_id) do
    customization = Demo.get_theme_customization(profile.id, theme_id)
    overrides = socket.assigns[:theme_overrides] || %{}

    socket
    |> assign(:theme_tokens, ThemeCustomizations.tokens(theme_id, customization, overrides))
    |> assign(:brand_logo_url, BrandLogo.display_url(profile))
  end

  @doc """
  Sanitizes a file path for background assets.
  Only allows alphanumeric, dots, dashes, and underscores.
  This prevents directory traversal and other injection attacks.
  """
  @spec sanitize_path(String.t() | nil) :: String.t()
  def sanitize_path(path), do: Validation.sanitize_path(path)

  @doc """
  Prepares common wrapper assigns for theme wrapper components.

  Derives `@background` (the tokens' `media[:background]`, the background
  descriptor, or nil), `@has_video_background` and `@show_language_switcher`
  so each theme wrapper doesn't duplicate this logic; wrappers never read the
  tokens' media themselves.

  `@show_language_switcher` is the wrapper's own choice when it passes one,
  else true on every step but the payment wait of a `Continuous` or
  `Transcript` page.
  """
  @spec prepare_wrapper_assigns(map()) :: map()
  def prepare_wrapper_assigns(assigns) do
    background = background(assigns[:theme_tokens])

    # The top bar (logo + language switcher, see PublicTopBar) is now a
    # persistent structural element shared with the public calendar page, not
    # just a floating language badge — it must stay visible on every step
    # rather than disappearing past :overview, or the page would visibly lose
    # its whole header when the visitor advances. Explicit callers (meeting
    # cancel/reschedule pages) can still opt out with `show_language_switcher={false}`.
    show_language_switcher =
      if is_boolean(assigns[:show_language_switcher]),
        do: assigns[:show_language_switcher],
        else: language_switcher?(assigns[:journey], assigns[:current_state])

    assigns
    |> assign(:background, background)
    |> assign(:has_video_background, match?(%{kind: :video}, background))
    |> assign(:show_language_switcher, show_language_switcher)
  end

  # The top bar is on every step (see above), bar the payment wait of a page
  # that opens its moments by itself: a locale change remounts the page on its
  # entry route, which would drop the wait for the checkout. The journey is
  # matched as a map, not as `%Journey{}`: a struct pattern would make every
  # wrapper that imports this module depend on the journey engine at compile
  # time.
  defp language_switcher?(journey, current_state),
    do: not (Reveal.journey?(journey) and current_state == :awaiting_payment)

  defp background(%Tokens{media: media}), do: media[:background]
  defp background(_no_tokens), do: nil
end
