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
  legible against that dark background.

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

  import TymeslotWeb.Components.CoreComponents, only: [icon: 1]
  import TymeslotWeb.Components.CoreComponents.Brand
  import TymeslotWeb.Components.LanguageSwitcher

  attr :locale, :string, required: true
  attr :locales, :list, required: true
  attr :dropdown_open, :boolean, default: false
  attr :theme, :string, default: "quill"
  attr :current_user, :map, default: nil
  attr :embedded, :boolean, default: false
  attr :username, :string, default: nil, doc: "organizer whose booking page the logo links to"

  @spec public_top_bar(map()) :: Phoenix.LiveView.Rendered.t()
  def public_top_bar(assigns) do
    ~H"""
    <div class="public-top-bar-wrapper">
      <nav class="public-top-bar">
        <div class="public-top-bar-brand">
          <%!-- Not linked when embedded: the link would leave the embed's token behind. --%>
          <%= if @username not in [nil, ""] and not @embedded do %>
            <.link
              navigate={~p"/#{@username}"}
              class="flex"
              aria-label={dgettext("common", "Booking page")}
              title={dgettext("common", "Booking page")}
            >
              <.logo mode={:full} variant={:dark} img_class="h-9 sm:h-12" />
            </.link>
          <% else %>
            <.logo mode={:full} variant={:dark} img_class="h-9 sm:h-12" />
          <% end %>
        </div>

        <div class="public-top-bar-actions">
          <%= unless @embedded do %>
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
