defmodule TymeslotWeb.Components.DashboardSidebar do
  @moduledoc """
  Left sidebar navigation component for the dashboard.
  Provides navigation links for all dashboard sections.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Phoenix.LiveView.JS
  alias Tymeslot.Analytics
  alias Tymeslot.Auth.AdminRoles
  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Scheduling.LinkAccessPolicy
  alias TymeslotWeb.Components.Dashboard.ProBadge

  # The Calendars item is marked current for its own action and for the
  # legacy `:integrations` action that redirects into it, so the highlight
  # is correct even mid-redirect.
  @calendars_actions [:calendar_integration, :integrations]

  @doc """
  Renders the left sidebar navigation.
  """
  attr :current_action, :atom, required: true
  attr :current_user, :any, default: nil
  attr :integration_status, :map, default: %{}
  attr :pending_approval_count, :integer, default: 0
  attr :profile, :any, default: nil
  attr :automations_allowed, :boolean, default: true
  attr :analytics_allowed, :boolean, default: true
  attr :contacts_allowed, :boolean, default: true
  attr :payments_allowed, :boolean, default: false
  attr :sidebar_extensions, :list, default: []

  @spec sidebar(map()) :: Phoenix.LiveView.Rendered.t()
  def sidebar(assigns) do
    ~H"""
    <%!-- Mobile Overlay --%>
    <div
      id="dashboard-sidebar-overlay"
      class="lg:hidden fixed inset-0 bg-black/50 z-30 dashboard-sidebar-overlay hidden"
      phx-click={close_sidebar_js()}
    >
    </div>

    <aside
      id="dashboard-sidebar"
      data-tour="sidebar-nav"
      class="dashboard-sidebar lg:w-64 w-80 h-screen lg:h-full overflow-y-auto lg:shrink-0 lg:relative fixed top-0 left-0 z-40 transform -translate-x-full lg:translate-x-0 transition-transform duration-300 ease-in-out"
    >
      <div class="p-6">
        <%!-- Mobile Close Button --%>
        <div class="lg:hidden flex items-center justify-between mb-6">
          <TymeslotWeb.Components.CoreComponents.logo
            mode={:full}
            variant={:auto}
            img_class="h-9 sm:h-12"
          />
          <button
            class="dashboard-sidebar-close p-3 rounded-xl bg-neutral-50 border-2 border-neutral-300 hover:bg-red-50 hover:border-red-100 transition-all"
            phx-click={close_sidebar_js()}
            aria-label={dgettext("dashboard_common", "Close sidebar")}
          >
            <.icon name="hero-x-mark" class="w-6 h-6 text-neutral-700 dark:text-neutral-200" />
          </button>
        </div>

        <%!-- Scheduling Link (Mobile and Desktop): open, copy, send by email.
             Icon-only so all three fit the sidebar width; labels live in
             title/aria-label. --%>
        <div :if={LinkAccessPolicy.can_link?(@profile, @integration_status)} class="mb-6 flex gap-2">
          <.link
            href={LinkAccessPolicy.scheduling_path(@profile)}
            target="_blank"
            class="dashboard-nav-link flex-1 flex items-center justify-center px-4 py-4 rounded-2xl transition-all duration-300 bg-linear-to-br from-primary-600 to-secondary-600 text-white hover:text-white hover:translate-x-0 hover:from-primary-700 hover:to-secondary-700 group"
            title={dgettext("dashboard_common", "Open booking page")}
            aria-label={dgettext("dashboard_common", "Open booking page")}
          >
            <.icon name="hero-arrow-top-right-on-square" class="w-5 h-5 shrink-0 text-white" />
          </.link>
          <button
            id="copy-scheduling-link"
            type="button"
            phx-hook="CopyOnClick"
            data-copy-text={"#{TymeslotWeb.Endpoint.url()}#{LinkAccessPolicy.scheduling_path(@profile)}"}
            data-copy-feedback={dgettext("dashboard_common", "Scheduling link copied to clipboard!")}
            class={sidebar_link_button_class()}
            title={dgettext("dashboard_common", "Copy link to clipboard")}
            aria-label={dgettext("dashboard_common", "Copy link to clipboard")}
          >
            <.icon name="hero-clipboard" class="w-5 h-5" />
          </button>
          <button
            id="email-scheduling-link"
            type="button"
            phx-click={JS.push(close_sidebar_js(), "open", target: "#share-links-modal")}
            class={sidebar_link_button_class()}
            title={dgettext("dashboard_common", "Send links by email")}
            aria-label={dgettext("dashboard_common", "Send links by email")}
          >
            <.icon name="hero-envelope" class="w-5 h-5" />
          </button>
        </div>
        <div :if={!LinkAccessPolicy.can_link?(@profile, @integration_status)} class="mb-6 flex gap-2">
          <button
            :for={icon <- ["hero-arrow-top-right-on-square", "hero-clipboard", "hero-envelope"]}
            type="button"
            disabled
            class="flex-1 flex items-center justify-center px-4 py-4 rounded-2xl bg-neutral-200 dark:bg-twilight-indigo-800 text-neutral-500 dark:text-twilight-indigo-300 cursor-not-allowed opacity-60 border-2 border-neutral-300 dark:border-twilight-indigo-700"
            title={LinkAccessPolicy.disabled_tooltip(@profile, @integration_status)}
          >
            <.icon name={icon} class="w-5 h-5" />
          </button>
        </div>

        <%!-- Navigation Links --%>
        <nav class="space-y-3 mt-6">
          <div>
            <div class="dashboard-nav-section-title">{dgettext("dashboard_common", "General")}</div>
            <div class="space-y-2">
              <.nav_link patch={~p"/dashboard/overview"} current={@current_action} action={:overview}>
                <.icon name="hero-home" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Overview")}</span>
              </.nav_link>

              <.nav_link patch={~p"/dashboard"} current={@current_action} action={:calendar}>
                <.icon name="hero-calendar-days" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Calendar")}</span>
              </.nav_link>

              <.nav_link
                patch={~p"/dashboard/meetings"}
                current={@current_action}
                action={:meetings}
                show_notification={@current_action != :meetings and @pending_approval_count > 0}
                notification_type="info"
                notification_title={
                  dgettext("dashboard_common", "You have meetings awaiting approval")
                }
              >
                <.icon name="hero-clock" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Meetings")}</span>
              </.nav_link>

              <.nav_link
                :if={Analytics.enabled?()}
                patch={~p"/dashboard/analytics"}
                current={@current_action}
                action={:analytics}
                locked={!@analytics_allowed}
              >
                <.icon name="hero-chart-bar" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Analytics")}</span>
                <ProBadge.pro_badge :if={!@analytics_allowed} data-testid="analytics-pro-badge" />
              </.nav_link>

              <.nav_link
                patch={~p"/dashboard/contacts"}
                current={@current_action}
                action={:contacts}
                locked={!@contacts_allowed}
              >
                <.icon name="hero-identification" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Contacts")}</span>
                <ProBadge.pro_badge :if={!@contacts_allowed} data-testid="contacts-pro-badge" />
              </.nav_link>
            </div>
          </div>

          <div>
            <div class="dashboard-nav-section-title">
              {dgettext("dashboard_common", "Scheduling")}
            </div>
            <div class="space-y-2">
              <.nav_link
                patch={~p"/dashboard/meeting-settings"}
                current={@current_action}
                action={:meeting_settings}
                show_notification={not (@integration_status[:has_meeting_types] || false)}
                notification_type="info"
                notification_title={
                  dgettext("dashboard_common", "Add a meeting type so guests have something to book")
                }
              >
                <.icon name="hero-squares-2x2" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Meeting Types")}</span>
              </.nav_link>

              <.nav_link
                patch={~p"/dashboard/availability"}
                current={@current_action}
                action={:availability}
              >
                <.icon name="hero-adjustments-horizontal" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Availability")}</span>
              </.nav_link>

              <.nav_link patch={~p"/dashboard/polls"} current={@current_action} action={:polls}>
                <.icon name="hero-hand-raised" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Polls")}</span>
              </.nav_link>

              <.nav_link
                patch={~p"/dashboard/theme"}
                current={
                  if @current_action == :theme_customization, do: :theme, else: @current_action
                }
                action={:theme}
              >
                <.icon name="hero-paint-brush" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Theme")}</span>
              </.nav_link>
            </div>
          </div>

          <div>
            <div class="dashboard-nav-section-title">
              {dgettext("dashboard_common", "Integrations")}
            </div>
            <div class="space-y-2">
              <.nav_link
                patch={~p"/dashboard/calendar-integration"}
                current={calendars_current(@current_action)}
                action={:calendar_integration}
                show_notification={not Map.get(@integration_status, :has_calendar, false)}
                notification_type="info"
                notification_title={
                  dgettext("dashboard_common", "Connect a calendar to finish setup")
                }
              >
                <.icon name="hero-puzzle-piece" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Calendars")}</span>
              </.nav_link>

              <.nav_link
                patch={~p"/dashboard/video-integration"}
                current={@current_action}
                action={:video_integration}
                show_notification={not Map.get(@integration_status, :has_video, false)}
                notification_type="info"
                notification_title={
                  dgettext("dashboard_common", "Connect a video provider to finish setup")
                }
              >
                <.icon name="hero-video-camera" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Video")}</span>
              </.nav_link>

              <.nav_link
                :if={@payments_allowed}
                patch={~p"/dashboard/payments"}
                current={@current_action}
                action={:payments}
              >
                <.icon name="hero-credit-card" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Payments")}</span>
              </.nav_link>
            </div>
          </div>

          <div>
            <div class="dashboard-nav-section-title">
              {dgettext("dashboard_common", "Distribution")}
            </div>
            <div class="space-y-2">
              <.nav_link patch={~p"/dashboard/embed"} current={@current_action} action={:embed}>
                <.icon name="hero-code-bracket" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Embed & Share")}</span>
              </.nav_link>
            </div>
          </div>

          <div>
            <div class="dashboard-nav-section-title">{dgettext("dashboard_common", "Workflow")}</div>
            <div class="space-y-2">
              <.nav_link
                patch={~p"/dashboard/automation"}
                current={@current_action}
                action={:automation}
                locked={!@automations_allowed}
              >
                <.icon name="hero-bolt" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Automation")}</span>
                <ProBadge.pro_badge :if={!@automations_allowed} data-testid="automation-pro-badge" />
              </.nav_link>

              <.nav_link
                :for={ext <- extensions_without_section(@sidebar_extensions)}
                navigate={ext.path}
                current={@current_action}
                action={ext.action}
              >
                <.icon name={ext.icon} class="w-5 h-5" />
                <span>{extension_label(ext.label)}</span>
              </.nav_link>
            </div>
          </div>

          <div :for={{section_title, exts} <- extension_sections(@sidebar_extensions)}>
            <div class="dashboard-nav-section-title">{extension_label(section_title)}</div>
            <div class="space-y-2">
              <.nav_link
                :for={ext <- exts}
                navigate={ext.path}
                current={@current_action}
                action={ext.action}
              >
                <.icon name={ext.icon} class="w-5 h-5" />
                <span>{extension_label(ext.label)}</span>
              </.nav_link>
            </div>
          </div>

          <div :if={@current_user && @current_user.is_admin && AdminRoles.admin_ui_enabled?()}>
            <div class="dashboard-nav-section-title">
              {dgettext("dashboard_common", "Administration")}
            </div>
            <div class="space-y-2">
              <.nav_link patch={~p"/dashboard/admin"} current={@current_action} action={:admin}>
                <.icon name="hero-shield-check" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "App Settings")}</span>
              </.nav_link>

              <.nav_link
                patch={~p"/dashboard/admin/users"}
                current={@current_action}
                action={:admin_users}
              >
                <.icon name="hero-users" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Users")}</span>
              </.nav_link>

              <.nav_link
                patch={~p"/dashboard/admin/audit"}
                current={@current_action}
                action={:admin_audit}
              >
                <.icon name="hero-clipboard-document-list" class="w-5 h-5" />
                <span>{dgettext("dashboard_common", "Audit log")}</span>
              </.nav_link>
            </div>
          </div>
        </nav>

        <%!-- AGPL section 13: offer the running version's source to every user --%>
        <p class="mt-8 px-4 text-token-xs text-neutral-400 dark:text-twilight-indigo-400">
          <a
            id="dashboard-source-code-link"
            href={Config.source_code_url()}
            target="_blank"
            rel="noopener noreferrer"
            class="underline hover:text-primary-600"
          >
            {dgettext("dashboard_common", "Source code")}
          </a>
          · AGPL-3.0
        </p>
      </div>
    </aside>
    """
  end

  # Sidebar extensions supply their labels as English strings via config. Each
  # extension owns its labels' translations in its own gettext catalogue, so the
  # {backend, domain} to localise through is configurable (:dashboard_extension_gettext)
  # and defaults to Core's shared nav domain. An unknown label falls back to the
  # English text unchanged.
  defp extension_label(label) do
    {backend, domain} =
      Application.get_env(
        :tymeslot,
        :dashboard_extension_gettext,
        {TymeslotWeb.Gettext, "dashboard_common"}
      )

    Gettext.dgettext(backend, domain, label)
  end

  # Collapses the Calendars action and the legacy `:integrations` action that
  # redirects into it, so the nav item highlights correctly for both.
  defp calendars_current(action) when action in @calendars_actions, do: :calendar_integration
  defp calendars_current(action), do: action

  # Extensions with no :section (Tymeslot.Dashboard.ExtensionSchema's own
  # moduledoc documents it as optional) render inside the built-in "Workflow"
  # section, next to Automation — today's behaviour, unchanged.
  defp extensions_without_section(sidebar_extensions) do
    Enum.reject(sidebar_extensions, &Map.has_key?(&1, :section))
  end

  # Extensions that DO declare :section get their own section, grouped by
  # that title, one group per distinct value in first-appearance order (so a
  # caller registering extensions in a stable order gets a stable sidebar).
  defp extension_sections(sidebar_extensions) do
    grouped =
      sidebar_extensions
      |> Enum.filter(&Map.has_key?(&1, :section))
      |> Enum.group_by(& &1.section)

    sidebar_extensions
    |> Enum.map(& &1[:section])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.map(&{&1, Map.fetch!(grouped, &1)})
  end

  defp sidebar_link_button_class do
    "dashboard-nav-link flex-1 flex items-center justify-center px-4 py-4 rounded-2xl transition-all duration-300 bg-white dark:bg-twilight-indigo-950 border-2 border-neutral-300 text-neutral-700 dark:text-neutral-200 hover:border-primary-400 cursor-pointer hover:text-primary-700 hover:translate-x-0 group"
  end

  defp close_sidebar_js do
    %JS{}
    |> JS.remove_class("dashboard-sidebar-open", to: "#dashboard-sidebar")
    |> JS.add_class("hidden", to: "#dashboard-sidebar-overlay")
  end

  # Private component for navigation links
  attr :patch, :string, default: nil
  attr :navigate, :string, default: nil
  attr :current, :atom, required: true
  attr :action, :atom, required: true
  attr :show_notification, :boolean, default: false
  attr :notification_type, :string, default: "critical"
  attr :notification_title, :string, default: nil
  attr :locked, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  @spec nav_link(map()) :: Phoenix.LiveView.Rendered.t()
  defp nav_link(assigns) do
    ~H"""
    <.link
      patch={@patch}
      navigate={@navigate}
      phx-click={close_sidebar_js()}
      {@rest}
      class={[
        "dashboard-nav-link flex items-center space-x-3 px-4 py-2 text-sm font-medium rounded-lg transition-all duration-200",
        if(@current == @action,
          do: "dashboard-nav-link--active",
          else: ""
        ),
        if(@show_notification and @current != @action,
          do: "dashboard-nav-link--needs-setup",
          else: ""
        ),
        if(@locked, do: "opacity-75", else: "")
      ]}
    >
      {render_slot(@inner_block)}
      <%!-- Notification Badge --%>
      <div
        :if={@show_notification}
        class={[
          "dashboard-nav-notification",
          case @notification_type do
            "warning" -> "dashboard-nav-notification--warning"
            "info" -> "dashboard-nav-notification--info"
            _other -> ""
          end
        ]}
        title={@notification_title || dgettext("dashboard_common", "Setup recommended")}
      >
        !
      </div>
    </.link>
    """
  end
end
