defmodule TymeslotWeb.Dashboard.Admin.HubComponent do
  @moduledoc """
  Admin dashboard: Settings (`:admin`), Users (`:admin_users`) and the
  security Audit log (`:admin_audit`), rendered
  inside the regular dashboard chrome (sidebar + top nav) instead of a
  standalone page. Each has its own sidebar entry under "Administration"
  ("App Settings" and "Users") — there is no in-page tab switcher, `update/2`
  simply loads whichever data the current `live_action` needs and `render/1`
  shows the matching view.

  `ComponentDispatch.component_id/1` gives both actions the same id, so this
  is a single persistent component across the two pages rather than one that
  gets unmounted and remounted on every patch between them. The Settings side
  has its own inner tab bar too: `:authentication`/`:email`/`:general`, per
  `TymeslotWeb.AdminLive.Tabs`.

  Route-level admin enforcement lives in `DashboardLive`'s `handle_params/3`
  (it redirects a non-admin, or a deployment with the admin UI disabled,
  before this component ever mounts). Phoenix does not route LiveComponent
  events through the parent LiveView's hooks, so every state-changing event
  handled here re-verifies admin status against the database first via
  `with_admin/2` — the same defence `TymeslotWeb.Hooks.EnsureAdminHook` gave
  the old standalone `/admin` LiveView, so a session whose admin status is
  revoked mid-visit (in another session) cannot keep issuing admin actions.
  """

  use TymeslotWeb, :live_component
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.AppSettings
  alias Tymeslot.Auth
  alias Tymeslot.Auth.UserSchema
  alias Tymeslot.Emails.Branding
  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Locales
  alias Tymeslot.MeetingPayments
  alias Tymeslot.Pagination.OffsetPage
  alias TymeslotWeb.AdminLive.Tabs
  alias TymeslotWeb.Dashboard.Admin.AuditActions
  alias TymeslotWeb.Dashboard.Admin.AuditView
  alias TymeslotWeb.Dashboard.Admin.SettingsActions
  alias TymeslotWeb.Dashboard.Admin.SettingsView
  alias TymeslotWeb.Dashboard.Admin.UsersActions
  alias TymeslotWeb.Dashboard.Admin.UsersView
  alias TymeslotWeb.Live.Shared.Flash

  require Logger

  # A 300px-wide PNG lands far under this; the cap is a backstop against a
  # client that ignores the hook and posts something else entirely. The sole
  # declaration of the limit: it feeds `allow_upload/3` below, the interpolated
  # "too large" message, and (via `SettingsView.email_logo_row/1`'s `max_bytes`
  # attr) the client-side guard in the upload hook.
  @logo_max_bytes 2_000_000

  @impl Phoenix.LiveComponent
  def mount(socket) do
    {:ok,
     socket
     |> assign(:pending_action, nil)
     |> assign(:pending_action_submitting, false)
     |> assign(:user_search, "")
     |> assign(:users_page, 1)
     |> assign(:users_per_page, OffsetPage.default_page_size())
     |> assign(:max_logo_bytes, @logo_max_bytes)
     |> assign(:active_settings_tab, List.first(Tabs.settings_tabs()))
     |> assign(:site_banner_locale, Locales.default_locale())
     |> AuditActions.init()
     |> allow_upload(:email_logo,
       accept: ~w(.png),
       max_entries: 1,
       max_file_size: @logo_max_bytes,
       auto_upload: true,
       progress: &SettingsActions.handle_logo_progress/3
     )}
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    previous_action = socket.assigns[:live_action]
    socket = assign(socket, assigns)

    # Since :admin and :admin_users share one persistent component id (see
    # `ComponentDispatch.component_id/1`), this component keeps running
    # across a patch between them instead of remounting — clear any
    # in-flight promote/demote confirmation left over from the Users tab so
    # it can't resurface stale after navigating away and back. Guarded to
    # only fire on an actual tab change, not every unrelated re-render (a
    # PubSub event, the agenda tick, ...) while already sitting on a tab.
    socket =
      if previous_action in [nil, socket.assigns.live_action] do
        socket
      else
        UsersActions.clear_pending_action(socket)
      end

    {:ok,
     case socket.assigns.live_action do
       :admin_users ->
         load_users_data(socket, socket.assigns.user_search)

       :admin_audit ->
         AuditActions.load(socket)

       _settings ->
         load_settings_data(socket)
     end}
  end

  # Loads the current page (`users_page`, `users_per_page`) of the Users
  # tab's list together with each user's Connect account
  # country (batched in one query via `live_for_users/1` instead of one query
  # per row) so `UsersView` can render the Country column without an N+1.
  #
  # Public: also called from `UsersActions` after a promote/demote/delete/
  # disable/enable write, since the reload is tied to this component's own
  # assign structure rather than being a pure function of its arguments.
  @spec load_users_data(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def load_users_data(socket, search) do
    page = Auth.list_users_page(search, socket.assigns.users_page, socket.assigns.users_per_page)
    users = page.entries
    user_countries = MeetingPayments.get_connect_accounts_for_users(Enum.map(users, & &1.id))

    assign(socket,
      users: users,
      users_page: page.page,
      users_per_page: page.per_page,
      users_total: page.total,
      users_total_pages: page.total_pages,
      user_count: Auth.count_users(),
      admin_count: Auth.count_admins(),
      user_countries: user_countries
    )
  end

  # Re-reads `effective_values` and the email-branding preview data
  # (logo/accent) together, so every path that can change either one — the
  # generic settings save, and the branding-specific logo/accent handlers
  # below — refreshes both the same way.
  #
  # Public: also called from `SettingsActions` after every settings/logo
  # write, for the same reason `load_users_data/2` is.
  @spec load_settings_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def load_settings_data(socket) do
    effective_values = AppSettings.effective_values()
    accent = Map.fetch!(effective_values, :email_brand_accent).value

    socket
    |> assign(:effective_values, effective_values)
    |> assign(:email_logo_url, Branding.logo_url())
    |> assign(:stock_accent, Branding.stock_accent())
    |> assign(:accent_preview, Branding.accent_preview(accent))
  end

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div id="admin-hub">
      <.section_header
        icon={header_icon(@live_action)}
        title={header_title(@live_action)}
        subtitle={header_subtitle(@live_action)}
      />

      <SettingsView.settings_tab
        :if={@live_action == :admin}
        tab={@active_settings_tab}
        viewer={@current_user}
        site_banner_locale={@site_banner_locale}
        effective_values={@effective_values}
        email_logo_url={@email_logo_url}
        upload={@uploads.email_logo}
        logo_errors={SettingsActions.logo_error_messages(@uploads.email_logo)}
        stock_accent={@stock_accent}
        accent_preview={@accent_preview}
        max_logo_bytes={@max_logo_bytes}
        target={@myself}
      />

      <UsersView.users_tab
        :if={@live_action == :admin_users}
        users={@users}
        current_user={@current_user}
        user_count={@user_count}
        admin_count={@admin_count}
        user_countries={@user_countries}
        search_term={@user_search}
        page={@users_page}
        per_page={@users_per_page}
        total={@users_total}
        total_pages={@users_total_pages}
        pending_action={@pending_action}
        pending_action_submitting={@pending_action_submitting}
        target={@myself}
      />

      <AuditView.audit_tab
        :if={@live_action == :admin_audit}
        events={@audit_events}
        emails={@audit_emails}
        event_types={@audit_event_types}
        filters={@audit_filters}
        page={@audit_page}
        per_page={@audit_per_page}
        total={@audit_total}
        total_pages={@audit_total_pages}
        retention_days={@audit_retention_days}
        target={@myself}
      />
    </div>
    """
  end

  defp header_icon(:admin_users), do: "hero-users"
  defp header_icon(:admin_audit), do: "hero-clipboard-document-list"
  defp header_icon(_settings), do: "hero-cog-6-tooth"

  defp header_title(:admin_users), do: dgettext("dashboard_admin", "Users")
  defp header_title(:admin_audit), do: dgettext("dashboard_admin", "Audit log")
  defp header_title(_settings), do: dgettext("dashboard_admin", "Admin")

  defp header_subtitle(:admin_users) do
    dgettext("dashboard_admin", "List and manage registered users.")
  end

  defp header_subtitle(:admin_audit) do
    dgettext(
      "dashboard_admin",
      "Sign-ins, account changes and admin actions, kept for a limited time."
    )
  end

  defp header_subtitle(_settings) do
    dgettext("dashboard_admin", "Manage this self-hosted %{app_name} install.",
      app_name: Config.app_name()
    )
  end

  # --- Re-verification ---

  # Re-checks admin status against the database before running a
  # state-changing event. See the moduledoc for why this can't be handled
  # once, upstream, the way `EnsureAdminHook` did for the old standalone
  # LiveView.
  #
  # No accompanying flash here: `put_flash/3` on a component's own socket is
  # silently dropped (see `Flash`'s moduledoc), and forwarding it via
  # `Flash.put_flash/3` would race the synchronous `push_navigate` below —
  # this LiveView tears down as soon as the redirect is sent, before the
  # forwarded `{:flash, ...}` message could ever be handled. The redirect
  # itself is what matters for security; losing the explanation flash for
  # this rare mid-session-revocation case is an acceptable trade-off.
  defp with_admin(socket, fun) do
    case Auth.get_user(socket.assigns.current_user.id) do
      {:ok, %UserSchema{is_admin: true} = user} ->
        fun.(assign(socket, :current_user, user))

      _other ->
        {:noreply, push_navigate(socket, to: ~p"/dashboard")}
    end
  end

  # --- Settings tab events ---

  # Which of Authentication/Email/General is showing lives entirely in this
  # component's own state rather than the URL or `live_action` — the hub's
  # top level already spends `live_action` distinguishing Settings from
  # Users (see the moduledoc), so a second axis of routing for the settings
  # sub-tabs would mean stacking two different navigation schemes on one
  # page. Traded off deliberately: switching sub-tabs isn't bookmarkable or
  # shareable by URL, unlike the top-level Settings/Users split.
  @impl Phoenix.LiveComponent
  def handle_event("switch_settings_tab", %{"option" => tab}, socket) do
    with_admin(socket, fn socket ->
      if tab in Enum.map(Tabs.settings_tabs(), &to_string/1) do
        {:noreply, assign(socket, :active_settings_tab, String.to_existing_atom(tab))}
      else
        {:noreply, socket}
      end
    end)
  end

  # The site banner message's language tabs, same convention as the
  # organiser-content translation forms: the default-locale tab edits the
  # base `site_banner_message`, every other tab that locale's row of
  # `site_banner_translations`. Assigns only, never persists on its own.
  def handle_event("switch_site_banner_locale", %{"option" => locale}, socket) do
    if locale in Locales.supported_codes() do
      {:noreply, assign(socket, :site_banner_locale, locale)}
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "save_site_banner_translation",
        %{"locale" => locale, "value" => value},
        socket
      ) do
    with_admin(socket, fn socket ->
      SettingsActions.handle_site_banner_translation(socket, locale, value)
    end)
  end

  @impl Phoenix.LiveComponent
  def handle_event("set_setting", %{"key" => key, "state" => state}, socket) do
    with_admin(socket, fn socket ->
      with {:ok, atom_key} <- SettingsActions.parse_setting_key(key),
           {:ok, parsed} <- SettingsActions.parse_setting_value(state) do
        SettingsActions.handle_setting_update(socket, atom_key, parsed, state)
      else
        _other ->
          {:noreply,
           Flash.put_flash(
             socket,
             :error,
             dgettext("dashboard_admin", "Could not update setting.")
           )}
      end
    end)
  end

  # Submit handler used by score and email inputs that don't fit the
  # two-state Enabled/Disabled toggle pattern. Score inputs autosave on blur
  # via `phx-change`, so the handler short-circuits when the value is
  # unchanged to avoid spurious flashes on tab-through.
  def handle_event("save_setting", %{"key" => key} = params, socket) do
    with_admin(socket, fn socket ->
      raw_value = Map.get(params, "value", "")

      with {:ok, atom_key} <- SettingsActions.parse_setting_key(key),
           {:ok, value} <- SettingsActions.parse_typed_value(atom_key, raw_value),
           :changed <- SettingsActions.detect_change(socket, atom_key, value) do
        SettingsActions.handle_typed_setting_update(socket, atom_key, value)
      else
        # Submitting the value already in effect (e.g. a built-in default the
        # field was pre-populated with) is a legitimate no-op, not an error -
        # acknowledge it with the same saved pulse a real write gets so the
        # button doesn't look like it did nothing.
        :unchanged ->
          {:noreply, push_event(socket, "ts:setting-saved", %{key: key})}

        :invalid ->
          {:noreply, Flash.put_flash(socket, :error, SettingsActions.value_invalid_message(key))}

        _other ->
          {:noreply,
           Flash.put_flash(
             socket,
             :error,
             dgettext("dashboard_admin", "Could not update setting.")
           )}
      end
    end)
  end

  # The locale buttons carry their choice in `phx-value-locale` rather than a
  # form field, but everything downstream - the supported-set check, change
  # detection, the flash, the error path - is identical to a typed setting
  # save, so this reshapes the params and delegates rather than growing a
  # second copy of that pipeline. An empty string clears the override, exactly
  # as the blank option did.
  def handle_event("set_locale", %{"key" => key, "locale" => locale}, socket) do
    handle_event("save_setting", %{"key" => key, "value" => locale}, socket)
  end

  # --- Email branding events ---
  # The accent swatch used to be preview-only (a separate `preview_accent`
  # event updating a draft the hex field mirrored) to avoid its own persist
  # racing a typed-but-unsubmitted hex value. Both controls are blur-debounced
  # single-connection LiveView events now, processed strictly in the order the
  # admin triggered them, so routing the swatch through the same
  # `"save_setting"` event as every other typed setting (see
  # `EmailBrandingRows.brand_accent_row/1`) is safe: whichever control the
  # admin touched last determines the final value, same as any other setting
  # on this page.

  # Required by the upload form's phx-change. The work happens in
  # `handle_logo_progress/3` once the auto-upload completes; this only needs
  # to re-render so validation errors reach the page.
  def handle_event("validate_email_logo", _params, socket), do: {:noreply, socket}

  # Pushed by the upload hook when the browser cannot decode the file the
  # admin picked — a corrupt PNG, or an SVG that references resources the
  # canvas render cannot resolve. Nothing was uploaded, so this only reports.
  def handle_event("email_logo_conversion_failed", _params, socket) do
    with_admin(socket, fn socket ->
      {:noreply,
       Flash.put_flash(
         socket,
         :error,
         dgettext("dashboard_admin", "That image could not be read. Try a PNG or JPEG.")
       )}
    end)
  end

  # Pushed by the upload hook when the picked source file is too large to be
  # worth rasterising at all. Rejected before `readAsDataURL`, so nothing was
  # read or uploaded.
  def handle_event("email_logo_too_large", _params, socket) do
    with_admin(socket, fn socket ->
      {:noreply, Flash.put_flash(socket, :error, logo_too_large_message())}
    end)
  end

  def handle_event("remove_email_logo", _params, socket) do
    with_admin(socket, fn socket ->
      case Branding.remove_logo() do
        :ok ->
          {:noreply,
           socket
           |> Flash.put_flash(:info, dgettext("dashboard_admin", "Email logo removed."))
           |> load_settings_data()}

        {:error, reason} ->
          Logger.warning("Failed to remove email logo", reason: LogFormat.reason(reason))

          {:noreply,
           Flash.put_flash(
             socket,
             :error,
             dgettext("dashboard_admin", "Could not remove the logo.")
           )}
      end
    end)
  end

  # --- Audit tab events ---

  def handle_event("filter_audit", %{"audit" => params}, socket) do
    with_admin(socket, &{:noreply, AuditActions.filter(&1, params)})
  end

  def handle_event("audit_page", %{"page" => page}, socket) do
    with_admin(socket, &{:noreply, AuditActions.go_to_page(&1, page)})
  end

  def handle_event("audit_per_page", %{"audit_paging" => %{"per_page" => per_page}}, socket) do
    with_admin(socket, &{:noreply, AuditActions.set_per_page(&1, per_page)})
  end

  def handle_event("toggle_booking_attachment_type", %{"type" => type}, socket) do
    with_admin(socket, &SettingsActions.toggle_booking_attachment_type(&1, type))
  end

  def handle_event("set_audit_event", %{"key" => key, "state" => state}, socket) do
    with_admin(socket, &AuditActions.set_event_category(&1, key, state))
  end

  # --- Users tab events: search ---

  def handle_event("search_users", %{"term" => term}, socket) do
    with_admin(socket, fn socket ->
      {:noreply,
       socket
       |> assign(:user_search, term)
       |> assign(:users_page, 1)
       |> load_users_data(term)}
    end)
  end

  def handle_event("users_page", %{"page" => page}, socket) do
    with_admin(socket, fn socket ->
      case OffsetPage.parse_page(page) do
        {:ok, number} ->
          {:noreply,
           socket |> assign(:users_page, number) |> load_users_data(socket.assigns.user_search)}

        :error ->
          {:noreply, socket}
      end
    end)
  end

  def handle_event("users_per_page", %{"users_paging" => %{"per_page" => per_page}}, socket) do
    with_admin(socket, fn socket ->
      case OffsetPage.parse_per_page(per_page) do
        {:ok, size} ->
          {:noreply,
           socket
           |> assign(:users_per_page, size)
           |> assign(:users_page, 1)
           |> load_users_data(socket.assigns.user_search)}

        :error ->
          {:noreply, socket}
      end
    end)
  end

  # --- Users tab events: role-change flow ---

  def handle_event("request_promote", params, socket),
    do: with_admin(socket, &UsersActions.open_pending_action(:promote, params, &1))

  def handle_event("request_demote", params, socket),
    do: with_admin(socket, &UsersActions.open_pending_action(:demote, params, &1))

  def handle_event("cancel_pending_action", _params, socket) do
    {:noreply, UsersActions.clear_pending_action(socket)}
  end

  def handle_event("promote_user", %{"id" => id}, socket) do
    with_admin(
      socket,
      &UsersActions.with_user_id(id, &1, fn user_id, socket ->
        UsersActions.handle_promote(user_id, assign(socket, :pending_action_submitting, true))
      end)
    )
  end

  def handle_event("demote_user", %{"id" => id}, socket) do
    with_admin(
      socket,
      &UsersActions.with_user_id(id, &1, fn user_id, socket ->
        UsersActions.handle_demote(user_id, assign(socket, :pending_action_submitting, true))
      end)
    )
  end

  # --- Users tab events: delete / disable / enable flow ---

  def handle_event("request_delete", params, socket),
    do: with_admin(socket, &UsersActions.open_pending_action(:delete, params, &1))

  def handle_event("request_disable", params, socket),
    do: with_admin(socket, &UsersActions.open_pending_action(:disable, params, &1))

  def handle_event("request_enable", params, socket),
    do: with_admin(socket, &UsersActions.open_pending_action(:enable, params, &1))

  def handle_event("delete_user", %{"id" => id}, socket) do
    with_admin(
      socket,
      &UsersActions.with_user_id(id, &1, fn user_id, socket ->
        UsersActions.handle_delete(user_id, assign(socket, :pending_action_submitting, true))
      end)
    )
  end

  def handle_event("disable_user", %{"id" => id}, socket) do
    with_admin(
      socket,
      &UsersActions.with_user_id(id, &1, fn user_id, socket ->
        UsersActions.handle_disable(user_id, assign(socket, :pending_action_submitting, true))
      end)
    )
  end

  def handle_event("enable_user", %{"id" => id}, socket) do
    with_admin(
      socket,
      &UsersActions.with_user_id(id, &1, fn user_id, socket ->
        UsersActions.handle_enable(user_id, assign(socket, :pending_action_submitting, true))
      end)
    )
  end

  # Called from `SettingsActions.upload_error_message/1` too, so the
  # framework-level `:too_large` upload error phrases the limit identically
  # without a second place hardcoding it — `@logo_max_bytes` above is the
  # only place the number lives.
  @doc false
  @spec logo_too_large_message() :: String.t()
  def logo_too_large_message do
    dgettext(
      "dashboard_admin",
      "That image is too large. Pick one under %{limit}.",
      limit: logo_max_size_label()
    )
  end

  defp logo_max_size_label, do: "#{div(@logo_max_bytes, 1_000_000)} MB"
end
