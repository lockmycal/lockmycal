defmodule TymeslotWeb.Components.PublicTopBar do
  @moduledoc """
  Shared top bar for unauthenticated public-facing pages that use a scheduling
  theme's CSS (the booking flow, the public read-only calendar): the same
  full logo lockup shown in the dashboard (icon + wordmark + tagline, via
  `CoreComponents.Brand.logo/1` with `mode: :full`) on the left, the language
  switcher on the right — structurally mirroring the dashboard's
  `top_navigation/1` (logo left, single action right) but skinned with each
  booking theme's dark glass palette instead of the dashboard's light one.
  Given the organizer's `username`, the logo links to their booking page.
  The logo uses `variant: :dark` (a light-coloured wordmark) so it stays
  legible against that dark background. Given a `brand_logo_url` (the
  organizer's own logo, `Tymeslot.Profiles.BrandLogo.display_url/1`), that
  image replaces the app logo.

  Rendered from a single place (here) so `TymeslotWeb.Themes.Quill.Scheduling.Wrapper`,
  `TymeslotWeb.Themes.Rhythm.Scheduling.Wrapper`, and `TymeslotWeb.Public.CalendarLive`
  all stay in sync automatically — editing this file changes the bar on every
  booking step, on both themes, and on the public calendar page alike.
  """
  use TymeslotWeb, :verified_routes
  use Phoenix.Component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config
  alias TymeslotWeb.Live.Shared.DocsUrl

  import TymeslotWeb.Components.CoreComponents.Icons, only: [icon: 1]
  import TymeslotWeb.Components.CoreComponents.Brand
  import TymeslotWeb.Components.LanguageSwitcher

  attr :locale, :string, required: true
  attr :locales, :list, required: true
  attr :dropdown_open, :boolean, default: false
  attr :theme, :string, default: "quill"
  attr :current_user, :map, default: nil
  attr :embedded, :boolean, default: false
  attr :username, :string, default: nil, doc: "organizer whose booking page the logo links to"

  attr :brand_logo_url, :string,
    default: nil,
    doc: "organizer's own logo, shown instead of the app logo"

  @spec public_top_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def public_top_bar(assigns) do
    ~H"""
    <div class="public-top-bar-wrapper">
      <nav class={["public-top-bar", @embedded && "public-top-bar--embedded"]}>
        <div class="public-top-bar-brand">
          <%!-- Not linked when embedded: the link would leave the embed's token behind. --%>
          <%= if @username not in [nil, ""] and not @embedded do %>
            <.link
              navigate={~p"/#{@username}"}
              class="flex"
              aria-label={dgettext("common", "Booking page")}
              title={dgettext("common", "Booking page")}
            >
              <.top_bar_logo brand_logo_url={@brand_logo_url} />
            </.link>
          <% else %>
            <.top_bar_logo brand_logo_url={@brand_logo_url} />
          <% end %>
        </div>

        <%!-- Embedded, the bar carries only the logo, centred: the widget
             follows the visitor's browser language (`LocalePlug`), so it
             offers no switcher, and the account links belong to this site,
             not the one embedding it. --%>
        <div :if={!@embedded} class="public-top-bar-actions">
          <.top_bar_icon_link
            href={DocsUrl.home_url()}
            icon="hero-question-mark-circle"
            label={dgettext("common", "Documentation")}
          />
          <.top_bar_icon_link
            :if={website_url = Config.website_url()}
            href={website_url}
            icon="hero-globe-alt"
            label={dgettext("common", "Website")}
          />
          <%= if @current_user do %>
            <.link navigate={~p"/dashboard"} class="public-top-bar-link public-top-bar-link-outline">
              {dgettext("common", "Dashboard")}
            </.link>
          <% else %>
            <.link href={~p"/auth/login"} class="public-top-bar-link public-top-bar-link-outline">
              {dgettext("common", "Login")}
            </.link>
            <%= if Config.registration_enabled?() do %>
              <.link href={~p"/auth/signup"} class="public-top-bar-link public-top-bar-link-primary">
                {dgettext("common", "Get Started")}
              </.link>
            <% end %>
          <% end %>
          <.language_switcher
            locale={@locale}
            locales={@locales}
            dropdown_open={@dropdown_open}
            theme={@theme}
          />
        </div>
      </nav>
    </div>
    """
  end

  attr :brand_logo_url, :string, default: nil

  defp top_bar_logo(%{brand_logo_url: url} = assigns) when is_binary(url) do
    ~H"""
    <img
      src={@brand_logo_url}
      alt={dgettext("common", "Organizer logo")}
      class="public-top-bar-custom-logo h-9 sm:h-12 w-auto max-w-48 sm:max-w-64 object-contain"
    />
    """
  end

  defp top_bar_logo(assigns) do
    ~H"""
    <.logo mode={:full} variant={:dark} img_class="h-9 sm:h-12" />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp top_bar_icon_link(assigns) do
    ~H"""
    <a
      href={@href}
      target="_blank"
      rel="noopener noreferrer"
      class="public-top-bar-link public-top-bar-icon-link"
      aria-label={@label}
      title={@label}
    >
      <.icon name={@icon} class="w-5 h-5" />
    </a>
    """
  end
end
