defmodule TymeslotWeb.Shared.Auth.LayoutComponents do
  @moduledoc """
  Layout and container components for authentication pages.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Infrastructure.Config

  # A file dropped in at this path overrides the default login background gradient.
  @login_background_relative_path "priv/static/images/ui/backgrounds/login/LoginBackgroung.webp"
  @login_background_url "/images/ui/backgrounds/login/LoginBackgroung.webp"

  @spec auth_logo_header(map()) :: Phoenix.LiveView.Rendered.t()
  defp auth_logo_header(assigns) do
    assigns = assign_new(assigns, :subtitle, fn -> nil end)

    ~H"""
    <div class="flex flex-col items-center mb-8">
      <div class="mb-4 transform hover:scale-105 transition-all duration-300">
        <TymeslotWeb.Components.CoreComponents.Brand.logo mode={:full} img_class="h-14" />
      </div>
      <div class="text-center">
        <h1 class="text-2xl font-black text-neutral-900 tracking-tight">
          {@title}
        </h1>
        <%= if @subtitle do %>
          <p class="mt-1.5 text-neutral-500 font-medium max-w-sm mx-auto text-sm">
            {@subtitle}
          </p>
        <% end %>
      </div>
    </div>
    """
  end

  @spec auth_back_link(map()) :: Phoenix.LiveView.Rendered.t()
  defp auth_back_link(assigns) do
    ~H"""
    <%= if Config.logo_links_to_marketing?() do %>
      <a
        href={Config.site_home_path()}
        class="hidden sm:flex fixed top-6 left-6 items-center px-6 py-3 text-base font-bold bg-linear-to-br from-primary-600 to-secondary-600 text-white rounded-token-2xl hover:from-primary-700 hover:to-secondary-700 hover:-translate-y-1 transition-glass duration-300 group z-50"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          class="h-5 w-5 mr-2 transform group-hover:-translate-x-1 transition-transform duration-200"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z"
            clip-rule="evenodd"
          />
        </svg>
        {dgettext("auth", "Back to Website")}
      </a>
    <% end %>
    """
  end

  @spec auth_card_layout(map()) :: Phoenix.LiveView.Rendered.t()
  def auth_card_layout(assigns) do
    assigns =
      assigns
      |> assign_new(:subtitle, fn -> nil end)
      |> assign_new(:hide_legal_links, fn -> false end)
      |> assign(:login_background_url, login_background_url())

    ~H"""
    <main
      class={[
        "min-h-screen relative overflow-hidden flex items-center justify-center p-4 sm:p-6",
        is_nil(@login_background_url) &&
          "bg-linear-to-br from-primary-100 via-secondary-50 to-primary-200"
      ]}
      style={
        @login_background_url &&
          "background-image: url('#{@login_background_url}'); background-size: cover; background-position: center; background-repeat: no-repeat;"
      }
    >
      <%!-- Decorative blurred brand blobs give the background depth --%>
      <div
        :if={is_nil(@login_background_url)}
        aria-hidden="true"
        class="pointer-events-none absolute inset-0 overflow-hidden"
      >
        <div class="absolute -left-24 -top-24 h-96 w-96 rounded-token-full bg-primary-300/40 blur-3xl">
        </div>
        <div class="absolute -bottom-32 -right-16 h-[28rem] w-[28rem] rounded-token-full bg-secondary-300/40 blur-3xl">
        </div>
      </div>

      <.auth_back_link />

      <%!-- Content Overlay --%>
      <div class="w-full max-w-[500px] relative z-10 animate-in fade-in zoom-in-95 duration-700">
        <div class="auth-glass-card max-w-none!">
          <.auth_logo_header title={@title} subtitle={@subtitle} />

          {if assigns[:heading], do: render_slot(@heading)}

          <%!-- No flash group here: the `app` layout owns the only one, and
          `AuthLive` renders through it like every other LiveView. --%>

          <div class="space-y-6">
            {render_slot(@form)}

            <%!-- A `<:social :if={false}>` entry arrives as `[]`, not nil --%>
            <%= if assigns[:social] not in [nil, []] do %>
              <div class="relative py-2">
                <div class="absolute inset-0 flex items-center" aria-hidden="true">
                  <div class="w-full border-t border-neutral-300"></div>
                </div>
                <div class="relative flex justify-center text-token-2xs font-black uppercase tracking-[0.2em]">
                  <span class="bg-white px-4 text-neutral-400">
                    {dgettext("auth", "Or continue with")}
                  </span>
                </div>
              </div>
              {render_slot(@social)}
            <% end %>
          </div>

          <%= if assigns[:footer] do %>
            <div class="mt-8 pt-6 border-t-2 border-neutral-300">
              {render_slot(@footer)}
            </div>
          <% end %>
        </div>

        <.legal_links :if={!@hide_legal_links} />
      </div>
    </main>
    """
  end

  @doc """
  URL of the custom login background image, if a self-hoster/deployment has
  dropped one in at `@login_background_relative_path`, or `nil` to fall back
  to the default gradient. Public (not just used by `auth_card_layout/1`
  itself) so other pages that want the exact same background — e.g. the SaaS
  overlay's `LockmycalCloudWeb.LegalLive` — reuse this one check instead of
  duplicating it.
  """
  @spec login_background_url() :: String.t() | nil
  def login_background_url do
    if File.regular?(Application.app_dir(:tymeslot, @login_background_relative_path)) do
      @login_background_url
    end
  end

  @spec auth_footer(map()) :: Phoenix.LiveView.Rendered.t()
  def auth_footer(assigns) do
    assigns =
      assigns
      |> assign_new(:"phx-click", fn -> nil end)
      |> assign_new(:href, fn -> nil end)
      |> assign_new(:"phx-value-state", fn -> nil end)

    ~H"""
    <div class="text-center">
      <span class="text-sm text-neutral-500 font-bold">{@prompt}</span>
      <%= if assigns[:"phx-click"] do %>
        <button
          type="button"
          phx-click={assigns[:"phx-click"]}
          phx-value-state={assigns[:"phx-value-state"]}
          class="font-bold text-primary-600 hover:text-primary-700 transition-colors ml-2 bg-primary-50 hover:bg-primary-100 px-4 py-2 rounded-xl text-sm inline-block border-none cursor-pointer"
        >
          {@link_text}
        </button>
      <% else %>
        <a
          href={@href}
          class="font-bold text-primary-600 hover:text-primary-700 transition-colors ml-2 bg-primary-50 hover:bg-primary-100 px-4 py-2 rounded-xl text-sm inline-block"
        >
          {@link_text}
        </a>
      <% end %>
    </div>
    """
  end

  # Small print shown under every auth page's card (login included, per user
  # request). Signup passes `hide_legal_links={true}` to `auth_card_layout/1`
  # since it already spells out the same two links inside its own consent
  # checkbox (`terms_checkbox/1`) — showing both would just duplicate them on
  # that one page. Both URLs are nil by default for a bare self-host
  # (`config.exs`), matching `terms_checkbox/1`'s own guard, so this renders
  # nothing unless a deployment (e.g. the SaaS overlay) actually configures
  # them. No `dark:` companion here: unlike the dashboard, none of the auth
  # pages (background, card, headings) carry dark-mode styling yet, so a
  # solitary dark variant on just this line would be inconsistent rather
  # than helpful — see DESIGN_GUIDE.md's dark-mode section, scoped to "the
  # dashboard".
  @spec legal_links(map()) :: Phoenix.LiveView.Rendered.t()
  defp legal_links(assigns) do
    assigns =
      assigns
      |> assign(:terms_url, Application.get_env(:tymeslot, :legal_terms_url))
      |> assign(:privacy_url, Application.get_env(:tymeslot, :legal_privacy_url))

    ~H"""
    <%= if @terms_url && @privacy_url do %>
      <p class="mt-6 text-center text-token-xs text-neutral-500">
        <a
          href={@privacy_url}
          target="_blank"
          class="hover:text-primary-600 underline underline-offset-2"
        >
          {dgettext("auth", "Privacy Policy")}
        </a>
        <span class="mx-2" aria-hidden="true">·</span>
        <a
          href={@terms_url}
          target="_blank"
          class="hover:text-primary-600 underline underline-offset-2"
        >
          {dgettext("auth", "Terms of Service")}
        </a>
      </p>
    <% end %>
    """
  end
end
