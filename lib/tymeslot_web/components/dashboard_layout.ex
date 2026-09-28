defmodule TymeslotWeb.Components.DashboardLayout do
  @moduledoc """
  Shared layout component for all dashboard pages.
  Provides consistent navigation, styling, and user interface elements.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Tymeslot.SiteBanner
  alias TymeslotWeb.Components.DashboardSidebar
  alias TymeslotWeb.Components.SiteBanner, as: SiteBannerComponent
  alias TymeslotWeb.Components.UserDropdownComponent

  @doc """
  Renders the main dashboard layout with left sidebar and top navigation.
  """
  attr :current_user, :any, required: true
  attr :profile, :any, required: true
  attr :current_action, :atom, required: true
  attr :integration_status, :map, default: %{}
  attr :pending_approval_count, :integer, default: 0
  attr :automations_allowed, :boolean, default: true
  attr :analytics_allowed, :boolean, default: true
  attr :contacts_allowed, :boolean, default: true
  attr :payments_allowed, :boolean, default: false
  attr :full_width, :boolean, default: false
  attr :sidebar_extensions, :list, default: []
  attr :unseen_announcements, :list, default: []
  slot :inner_block, required: true

  @spec dashboard_layout(map()) :: Phoenix.LiveView.Rendered.t()
  def dashboard_layout(assigns) do
    ~H"""
    <div
      class="flex flex-col h-screen overflow-hidden"
      id="dashboard-root"
      phx-hook="ClipboardCopy"
    >
      <%!-- Feature-announcement carousel. Renders nothing when the list is empty. --%>
      <.live_component
        :if={@unseen_announcements != []}
        module={TymeslotWeb.Components.AnnouncementModalComponent}
        id="announcement-modal"
        announcements={@unseen_announcements}
        current_user={@current_user}
      />

      <%!-- Admin-configured site banner. Rendered here rather than in the root
           layout so it takes its height out of this viewport-tall column
           instead of pushing the column's bottom edge off-screen (see
           `TymeslotWeb.Layouts`' `@dashboard_layout_views`). --%>
      <SiteBannerComponent.site_banner banner={
        SiteBanner.for_surface(:app, Gettext.get_locale(TymeslotWeb.Gettext))
      } />

      <%!-- Top Navigation --%>
      <div class="shrink-0">
        <.top_navigation current_user={@current_user} profile={@profile} />
      </div>

      <%!-- Main Layout Area --%>
      <div class="flex lg:gap-8 flex-1 overflow-hidden min-h-0">
        <DashboardSidebar.sidebar
          current_action={@current_action}
          current_user={@current_user}
          integration_status={@integration_status}
          pending_approval_count={@pending_approval_count}
          profile={@profile}
          automations_allowed={@automations_allowed}
          analytics_allowed={@analytics_allowed}
          contacts_allowed={@contacts_allowed}
          payments_allowed={@payments_allowed}
          sidebar_extensions={@sidebar_extensions}
        />

        <%!-- Main Content Area --%>
        <div
          id="dashboard-content-container"
          class={
            [
              # `pt-6` matches the sidebar's own `p-6` padding (dashboard_sidebar.ex)
              # so the main content starts level with the "Booking" button.
              "flex-1 min-w-0 w-full lg:ml-0 pt-6",
              if(@full_width,
                do: "flex flex-col overflow-hidden",
                # `overflow-y-scroll` (not `-auto`) always reserves the
                # scrollbar's track width, whether or not the current page is
                # tall enough to need one — with `-auto`, a page shorter than
                # the viewport (e.g. Users) sits a scrollbar-width wider than a
                # taller one (e.g. Settings), visibly shifting the whole content
                # area sideways when patching between dashboard pages.
                # `scrollbar-gutter:stable` is kept alongside it for browsers
                # that render an always-visible `scroll` track more intrusively
                # than a reserved-but-invisible-when-unneeded gutter.
                else: "overflow-y-scroll [scrollbar-gutter:stable]"
              )
            ]
          }
          phx-hook="ScrollReset"
          data-action={@current_action}
        >
          <%= if @full_width do %>
            <main class="flex-1 flex flex-col min-h-0">{render_slot(@inner_block)}</main>
          <% else %>
            <div class="max-w-7xl mx-auto px-4 lg:px-8 pb-8">
              <main>{render_slot(@inner_block)}</main>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders the top navigation bar.
  """
  attr :current_user, :any, required: true
  attr :profile, :any, required: true
  attr :show_sidebar_toggle, :boolean, default: true

  @spec top_navigation(map()) :: Phoenix.LiveView.Rendered.t()
  def top_navigation(assigns) do
    ~H"""
    <div class="w-full">
      <nav class="brand-nav relative" style="z-index: 50;">
        <div class="w-full px-1 sm:px-4">
          <div class="flex items-center justify-between gap-2 h-16">
            <%!-- Left side: Logo and Mobile Menu Button --%>
            <div class="flex items-center space-x-2 sm:space-x-4 sm:-ml-4 flex-1 min-w-0">
              <%= if @show_sidebar_toggle do %>
                <%!-- Mobile Menu Button --%>
                <button
                  class="lg:hidden dashboard-mobile-menu-toggle flex items-center justify-center w-12 h-12 rounded-xl bg-neutral-50 dark:bg-twilight-indigo-900 border-2 border-neutral-300 dark:border-twilight-indigo-700 hover:bg-primary-50 dark:hover:bg-twilight-indigo-800 hover:border-primary-100 dark:hover:border-twilight-indigo-600 transition-all shrink-0"
                  phx-click={
                    JS.toggle_class("dashboard-sidebar-open", to: "#dashboard-sidebar")
                    |> JS.toggle_class("hidden", to: "#dashboard-sidebar-overlay")
                  }
                  aria-label={dgettext("dashboard_common", "Toggle sidebar")}
                >
                  <svg
                    class="w-6 h-6 text-neutral-700 dark:text-twilight-indigo-200"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2.5"
                      d="M4 6h16M4 12h16M4 18h16"
                    >
                    </path>
                  </svg>
                </button>
              <% end %>

              <%!-- Logo with Icon and Text --%>
              <div class="flex items-center space-x-3 min-w-0">
                <TymeslotWeb.Components.CoreComponents.logo
                  mode={:full}
                  variant={:auto}
                  img_class="h-9 sm:h-12 shrink min-w-0"
                />
              </div>
            </div>

            <%!-- Right side: appearance toggle + user dropdown --%>
            <div class="flex items-center gap-2 shrink-0">
              <button
                type="button"
                id="appearance-topbar-toggle"
                phx-hook="AppearanceToggle"
                data-appearance-flip
                class="flex items-center justify-center w-10 h-10 rounded-xl bg-neutral-50 dark:bg-twilight-indigo-900 border-2 border-neutral-300 dark:border-twilight-indigo-700 hover:bg-primary-50 dark:hover:bg-twilight-indigo-800 hover:border-primary-100 dark:hover:border-twilight-indigo-600 transition-all shrink-0"
                aria-label={dgettext("dashboard_common", "Toggle light/dark appearance")}
              >
                <.icon
                  name="hero-moon"
                  class="w-5 h-5 text-neutral-700 dark:text-neutral-200 dark:hidden"
                />
                <.icon
                  name="hero-sun"
                  class="w-5 h-5 hidden dark:block text-twilight-indigo-100"
                />
              </button>

              <div class="relative" data-tour="user-menu">
                <.live_component
                  module={UserDropdownComponent}
                  id="user-dropdown"
                  current_user={@current_user}
                  profile={@profile}
                />
              </div>
            </div>
          </div>
        </div>
      </nav>
    </div>
    """
  end
end
