defmodule TymeslotWeb.DashboardLive do
  @moduledoc """
  The dashboard for authenticated users: one LiveView behind every
  `/dashboard/*` section.

  The sections are LiveComponents rather than separate LiveViews, so switching
  between them patches the page instead of remounting it, and the sidebar,
  integration status and profile are loaded once for all of them.
  `TymeslotWeb.Dashboard.ComponentDispatch` maps the current `live_action` to
  the component to render.

  Because every section shares this process, its mailbox is where components
  talk to each other: a child asks for a sibling to be refreshed, or for a flash
  to be shown, by messaging the parent. `handle_info/2` is therefore mostly a
  routing table, with the calendar and meeting-type-form traffic delegated to
  `TymeslotWeb.Dashboard.CalendarEventHandlers` and
  `TymeslotWeb.Dashboard.MeetingFormMessages`.

  ## Extensions

  External applications can add their own sections without Core knowing they
  exist: they register sidebar entries and components through application
  config, and route their paths to this LiveView with a custom `live_action`.
  `Tymeslot.Dashboard.ExtensionSchema` is the contract, and documents the
  configuration keys, the component requirements and the routing pattern.
  """

  use TymeslotWeb, :live_view
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Auth
  alias Tymeslot.Dashboard.DashboardContext
  alias Tymeslot.Meetings
  alias Tymeslot.Onboarding
  alias Tymeslot.Scheduling.LinkAccessPolicy
  alias TymeslotWeb.Components.DashboardLayout
  alias TymeslotWeb.Components.TourOverlay
  alias TymeslotWeb.Dashboard.AutomationSettingsComponent
  alias TymeslotWeb.Dashboard.BookingsManagementComponent
  alias TymeslotWeb.Dashboard.CalendarEventHandlers
  alias TymeslotWeb.Dashboard.CalendarGridComponent
  alias TymeslotWeb.Dashboard.ComponentDispatch
  alias TymeslotWeb.Dashboard.MeetingFormMessages
  alias TymeslotWeb.Dashboard.PaymentsHandlers
  alias TymeslotWeb.Dashboard.PollEventHandlers
  alias TymeslotWeb.Dashboard.ScheduleSettingsComponent
  alias TymeslotWeb.Dashboard.ServiceSettingsComponent
  alias TymeslotWeb.Dashboard.Shared.ShareLinksModalComponent
  alias TymeslotWeb.Dashboard.TourEventHandlers
  alias TymeslotWeb.Helpers.PageTitles

  require Logger

  # Cadence for the overview agenda's live refresh — re-runs the DB query
  # every 60s (unlike the calendar grid's query-free `:tick`).
  @agenda_tick_ms 60_000

  # Calendars, Video and Payments are separate pages again. Only the old
  # merged-hub URL stays defined as a redirect (deep links, emails and old
  # bookmarks still point at it) to the new canonical Calendars action.
  @legacy_integrations_action :integrations

  # Both admin hub tabs — gated in handle_params below, see verify_admin/1.
  @admin_actions [:admin, :admin_users, :admin_audit]

  @impl Phoenix.LiveView
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) ::
          {:ok, Phoenix.LiveView.Socket.t()} | {:ok, Phoenix.LiveView.Socket.t(), keyword()}
  def mount(_params, _session, socket) do
    # Snapshot once, before the dashboard tour can mark itself seen mid-session,
    # so the overview greeting stays "Welcome" for the whole first visit and
    # only becomes "Welcome back" on a later one.
    first_visit? =
      case socket.assigns[:current_user] do
        %{} = user -> not Onboarding.dashboard_tour_seen?(user)
        _no_user -> false
      end

    # `:agenda` defaults nil so the calendar's Up-next strip can be guarded on
    # the dead render, before `load_dashboard_data/1` has run.
    {:ok, assign(socket, first_dashboard_visit: first_visit?, agenda: nil)}
  end

  @impl Phoenix.LiveView
  @spec handle_params(map(), String.t(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_params(params, _url, socket) do
    cond do
      socket.assigns.live_action in @admin_actions ->
        handle_admin_params(params, socket)

      socket.assigns.live_action == @legacy_integrations_action ->
        {:noreply, push_navigate(socket, to: ~p"/dashboard/calendar-integration")}

      true ->
        {:noreply, handle_dashboard_params(params, socket)}
    end
  end

  # The actual admin-access gate — re-checked on every patch (including
  # between the Settings and Users tabs). `Admin.HubComponent` re-checks
  # again per event, since a LiveComponent's events skip handle_params.
  defp handle_admin_params(params, socket) do
    case verify_admin(socket) do
      {:ok, socket} ->
        {:noreply, handle_dashboard_params(params, socket)}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Admin access required.")
         |> push_navigate(to: ~p"/dashboard")}
    end
  end

  defp verify_admin(socket) do
    with true <- Application.get_env(:tymeslot, :enable_admin_ui, true),
         {:ok, %{is_admin: true} = user} <- Auth.get_user(socket.assigns.current_user.id) do
      {:ok, assign(socket, :current_user, user)}
    else
      _other -> :error
    end
  end

  defp handle_dashboard_params(params, socket) do
    action = socket.assigns.live_action

    socket =
      if connected?(socket) && action == :calendar &&
           !socket.assigns[:calendar_pubsub_subscribed] do
        user_id = socket.assigns.current_user.id

        Phoenix.PubSub.subscribe(Tymeslot.PubSub, "calendar_events:#{user_id}")
        Meetings.subscribe_to_guest_rsvp_updates(user_id)

        assign(socket, :calendar_pubsub_subscribed, true)
      else
        socket
      end

    socket =
      socket
      |> assign(:page_title, PageTitles.dashboard_title(action))
      |> assign(:params, params)
      |> TourEventHandlers.assign_tour_state(action)

    socket =
      if action == :payments,
        do: PaymentsHandlers.maybe_enqueue_resync(params, socket),
        else: socket

    socket = if connected?(socket), do: load_dashboard_data(socket), else: socket
    reschedule_agenda_tick(socket, action)
  end

  # Keeps a single agenda-refresh timer alive only while a section that shows
  # the agenda (overview, calendar's Up-next strip) is open. Cancels any prior
  # timer first so repeated visits never stack ticks.
  defp reschedule_agenda_tick(socket, action) when action in [:overview, :calendar] do
    if ref = socket.assigns[:agenda_tick_ref], do: Process.cancel_timer(ref)

    if connected?(socket) do
      assign(socket, :agenda_tick_ref, Process.send_after(self(), :agenda_tick, @agenda_tick_ms))
    else
      assign(socket, :agenda_tick_ref, nil)
    end
  end

  defp reschedule_agenda_tick(socket, _action) do
    if ref = socket.assigns[:agenda_tick_ref], do: Process.cancel_timer(ref)
    assign(socket, :agenda_tick_ref, nil)
  end

  @impl Phoenix.LiveView
  @spec render(map()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        :component_module,
        ComponentDispatch.component_for_action(
          assigns.live_action,
          assigns[:dashboard_action_components]
        )
      )
      |> assign(:component_props, ComponentDispatch.props_for_action(assigns))
      |> assign(
        :should_render_feature,
        ComponentDispatch.should_render_feature?(assigns.live_action, assigns)
      )

    ~H"""
    <DashboardLayout.dashboard_layout
      current_user={@current_user}
      profile={@profile}
      current_action={@live_action}
      integration_status={@integration_status}
      pending_approval_count={@pending_approval_count}
      automations_allowed={@automations_allowed}
      analytics_allowed={@analytics_allowed}
      contacts_allowed={@contacts_allowed}
      payments_allowed={@payments_allowed}
      full_width={@live_action == :calendar}
      sidebar_extensions={@sidebar_extensions}
      unseen_announcements={@unseen_announcements}
    >
      <.live_component
        :if={@tour_active}
        module={TourOverlay}
        id="dashboard-tour-overlay"
        step={Enum.at(@tour_steps, @tour_step_index)}
        step_index={@tour_step_index}
        total_steps={@tour_total_steps}
      />
      <.live_component
        :if={LinkAccessPolicy.can_link?(@profile, @integration_status)}
        module={ShareLinksModalComponent}
        id="share-links-modal"
        current_user={@current_user}
        profile={@profile}
        integration_status={@integration_status}
        contacts_allowed={@contacts_allowed}
      />
      <%!-- Content --%>
      <div class={if @live_action == :calendar, do: "flex-1 flex flex-col min-h-0", else: ""}>
        <%!-- On :calendar, the checklist renders inside CalendarGrid.ComponentView,
              above the "up next" strip rather than above the page header. --%>
        <div class={
          if @live_action == :calendar, do: "flex-1 min-h-0 flex flex-col", else: "contents"
        }>
          <%= if @should_render_feature do %>
            <.live_component
              module={@component_module}
              id={ComponentDispatch.component_id(@live_action)}
              current_user={@current_user}
              first_dashboard_visit={@first_dashboard_visit}
              profile={Map.get(@component_props, :profile, @profile)}
              shared_data={Map.get(@component_props, :shared_data, %{})}
              integration_status={@integration_status}
              time_format={@time_format}
              agenda={@agenda}
              saving={@saving}
              client_ip={@client_ip}
              user_agent={@user_agent}
              live_action={@live_action}
              params={@params}
              custom_questions_allowed={@custom_questions_allowed}
              payments_allowed={@payments_allowed}
              contacts_allowed={@contacts_allowed}
              custom_username_allowed={@custom_username_allowed}
              custom_booking_link_allowed={@custom_booking_link_allowed}
            />
          <% else %>
            <ComponentDispatch.feature_placeholder
              section={@live_action}
              current_user={@current_user}
              feature_placeholder_components={@feature_placeholder_components}
            />
          <% end %>
        </div>
      </div>
    </DashboardLayout.dashboard_layout>
    """
  end

  # Handle events from child components
  @impl Phoenix.LiveView
  @spec handle_info({:profile_updated, map()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:profile_updated, profile}, socket) do
    {:noreply,
     socket
     |> assign(profile: profile)
     |> handle_saving_animation()
     |> refresh_dashboard_data()}
  end

  # The clock is resolved once at mount, so changing it in settings has to be
  # announced or the rest of the dashboard keeps rendering the old one until the
  # next full page load.
  @spec handle_info({:time_format_updated, String.t()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:time_format_updated, time_format}, socket) do
    {:noreply, assign(socket, time_format: time_format)}
  end

  # Keeps `@current_user` in sync after EmailSettingsFormComponent requests or
  # cancels an email change, mirroring :profile_updated above.
  @spec handle_info({:current_user_updated, Auth.UserSchema.t()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:current_user_updated, user}, socket) do
    {:noreply, assign(socket, :current_user, user)}
  end

  @spec handle_info(
          {:integration_added | :integration_removed | :integration_updated, any()},
          Phoenix.LiveView.Socket.t()
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({event, _type}, socket)
      when event in [:integration_added, :integration_removed, :integration_updated] do
    {:noreply,
     socket
     |> handle_saving_animation()
     |> refresh_dashboard_data()}
  end

  @spec handle_info({:meeting_type_changed}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:meeting_type_changed}, socket) do
    if socket.assigns.live_action == :meeting_settings do
      send_update(ServiceSettingsComponent, id: ComponentDispatch.component_id(:meeting_settings))
    end

    {:noreply,
     socket
     |> handle_saving_animation()
     |> refresh_dashboard_data()
     |> load_dashboard_data()}
  end

  @spec handle_info({:flash, {atom(), String.t()}}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:flash, {type, message}}, socket) do
    {:noreply, put_flash(socket, type, message)}
  end

  @impl Phoenix.LiveView
  def handle_info({:hide_saving, gen}, socket) do
    if gen == socket.assigns[:saving_gen] do
      {:noreply, assign(socket, saving: false, saving_timer_ref: nil)}
    else
      # Stale timer message from a cancelled generation — ignore
      {:noreply, socket}
    end
  end

  # Form-related messages forwarded from MeetingTypeForm and its child components
  # are delegated to TymeslotWeb.Dashboard.MeetingFormMessages.

  @impl Phoenix.LiveView
  def handle_info({:clear_reminder_confirmation, form_id}, socket),
    do: MeetingFormMessages.handle_clear_reminder_confirmation(form_id, socket)

  def handle_info({:refresh_calendar_list, form_id, integration_id}, socket),
    do: MeetingFormMessages.handle_refresh_calendar_list(form_id, integration_id, socket)

  def handle_info({:calendar_list_refreshed, form_id, _integration_id, calendars}, socket),
    do: MeetingFormMessages.handle_calendar_list_refreshed(form_id, calendars, socket)

  def handle_info({:retry_autosave, form_id}, socket),
    do: MeetingFormMessages.handle_retry_autosave(form_id, socket)

  # Generic external redirect message from components.
  # Only HTTPS URLs are allowed to prevent open-redirect attacks from
  # malicious or buggy extension components.
  @spec handle_info({:external_redirect, String.t()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:external_redirect, url}, socket) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
        {:noreply, redirect(socket, external: url)}

      _other ->
        Logger.warning("Rejected external redirect to non-HTTPS URL",
          url: url,
          user_id: socket.assigns[:current_user] && socket.assigns.current_user.id
        )

        {:noreply, put_flash(socket, :error, dgettext("dashboard_home", "Invalid redirect URL"))}
    end
  end

  @spec handle_info({:reload_schedule}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:reload_schedule}, socket) do
    # Refresh the availability component after mutations from child components
    send_update(ScheduleSettingsComponent,
      id: ComponentDispatch.component_id(:availability),
      profile: socket.assigns.profile
    )

    {:noreply, socket}
  end

  @spec handle_info({:telegram_linked, integer(), String.t()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:telegram_linked, integration_id, _chat_id}, socket) do
    send_update(AutomationSettingsComponent,
      id: ComponentDispatch.component_id(:automation),
      telegram_linked_integration_id: integration_id
    )

    {:noreply, socket}
  end

  @spec handle_info({:telegram_link_expired, integer()}, Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info({:telegram_link_expired, integration_id}, socket) do
    send_update(AutomationSettingsComponent,
      id: ComponentDispatch.component_id(:automation),
      telegram_link_expired_id: integration_id
    )

    {:noreply, socket}
  end

  # Poll-specific handle_info clauses — delegated to PollEventHandlers.

  def handle_info({:poll_updated, poll_id}, socket),
    do: PollEventHandlers.handle_poll_updated(poll_id, socket)

  def handle_info({:poll_slot_health, poll_id, health}, socket),
    do: PollEventHandlers.handle_poll_slot_health(poll_id, health, socket)

  # Calendar-specific handle_info clauses — delegated to CalendarEventHandlers.

  def handle_info({:guest_rsvp_updated, _meeting_id}, socket) do
    send_update(
      CalendarGridComponent,
      id: ComponentDispatch.component_id(:calendar),
      action: :refresh_guest_summaries
    )

    {:noreply, socket}
  end

  def handle_info(:tick, socket),
    do: CalendarEventHandlers.handle_tick(socket)

  def handle_info(:agenda_tick, socket) do
    {:noreply, socket |> reschedule_agenda_tick(socket.assigns.live_action) |> refresh_agenda()}
  end

  # Sent by CalendarGridComponent's visibility toggles (hidden_integration_ids
  # or per-calendar hidden_calendar_keys) — those are display preferences, not
  # an event mutation, so they don't otherwise go through rebuild_agenda/1.
  def handle_info(:calendar_visibility_changed, socket), do: {:noreply, refresh_agenda(socket)}

  def handle_info({:calendar_events_updated, _user_id, _changed_uids}, socket),
    do: socket |> CalendarEventHandlers.handle_calendar_events_updated() |> rebuild_agenda()

  def handle_info({:calendar_sync_complete, _user_id, _integration_id}, socket),
    do: CalendarEventHandlers.handle_calendar_sync_complete(socket)

  def handle_info(:calendar_sync_flash, socket),
    do: CalendarEventHandlers.handle_calendar_sync_flash(socket)

  def handle_info(:reset_calendar_sync, socket),
    do: CalendarEventHandlers.handle_reset_calendar_sync(socket)

  def handle_info({:event_update_result, result}, socket),
    do: result |> CalendarEventHandlers.handle_event_update_result(socket) |> rebuild_agenda()

  def handle_info({:event_move_result, result}, socket),
    do: result |> CalendarEventHandlers.handle_event_move_result(socket) |> rebuild_agenda()

  def handle_info({:event_video_result, result}, socket),
    do: CalendarEventHandlers.handle_event_video_result(result, socket)

  def handle_info({:execute_create_event, payload}, socket),
    do: CalendarEventHandlers.handle_execute_create_event(payload, socket)

  def handle_info({:create_event_result, result}, socket),
    do: result |> CalendarEventHandlers.handle_create_event_result(socket) |> rebuild_agenda()

  def handle_info({:execute_create_ad_hoc_meeting, params}, socket),
    do: CalendarEventHandlers.handle_execute_create_ad_hoc_meeting(params, socket)

  def handle_info({:create_ad_hoc_meeting_result, result}, socket),
    do:
      result
      |> CalendarEventHandlers.handle_create_ad_hoc_meeting_result(socket)
      |> rebuild_agenda()

  def handle_info({:execute_delete_event, payload}, socket),
    do: CalendarEventHandlers.handle_execute_delete_event(payload, socket)

  def handle_info({:delete_event_result, result}, socket),
    do: result |> CalendarEventHandlers.handle_delete_event_result(socket) |> rebuild_agenda()

  # Meetings-page "Quick add" dialog (event mode) — mirrors the calendar's
  # own :execute_create_event/:create_event_result pair above, but the
  # target is a LiveComponent, so the result is routed back via send_update/2
  # rather than a direct CalendarEventHandlers call.
  def handle_info({:quick_add_event_created, result}, socket) do
    send_update(BookingsManagementComponent,
      id: ComponentDispatch.component_id(:meetings),
      action: :quick_add_event_created,
      result: result
    )

    rebuild_agenda({:noreply, socket})
  end

  @spec handle_info(any(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_info(_msg, socket) do
    # Silently ignore unhandled messages
    {:noreply, socket}
  end

  @impl Phoenix.LiveView
  @spec handle_event(String.t(), map(), Phoenix.LiveView.Socket.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_event("tour:" <> action, params, socket),
    do: TourEventHandlers.handle_event(action, params, socket)

  def handle_event("onboarding:toggle", %{"id" => key}, socket) do
    case Onboarding.toggle_dashboard_setup_item(socket.assigns.current_user, key) do
      {:ok, user} -> {:noreply, assign(socket, :current_user, user)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("onboarding:dismiss", _params, socket) do
    case Onboarding.dismiss_dashboard_setup(socket.assigns.current_user) do
      {:ok, user} -> {:noreply, assign(socket, :current_user, user)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  # Fired by the topbar sun/moon quick toggle (DashboardLayout.top_navigation/1,
  # AppearanceToggle JS hook) — a plain function component, not a LiveComponent,
  # so the click lands directly here rather than on a component's handle_event.
  # The fuller Light/Dark/System control lives on Profile Settings
  # (AppearanceFormComponent); this is just the two-way quick flip, and the hook
  # already applied the class client-side before this round-trip returns.
  def handle_event("change_appearance", %{"value" => value}, socket) do
    case Auth.update_user_theme_preference(socket.assigns.current_user, value) do
      {:ok, user} -> {:noreply, assign(socket, :current_user, user)}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  # Private functions

  @spec handle_saving_animation(Phoenix.LiveView.Socket.t(), non_neg_integer()) ::
          Phoenix.LiveView.Socket.t()
  defp handle_saving_animation(socket, duration \\ 1000) do
    if ref = socket.assigns[:saving_timer_ref] do
      Process.cancel_timer(ref)
    end

    gen = (socket.assigns[:saving_gen] || 0) + 1
    ref = Process.send_after(self(), {:hide_saving, gen}, duration)
    assign(socket, saving: true, saving_timer_ref: ref, saving_gen: gen)
  end

  # Refreshes integration status only — used after integration events.
  # Action-specific data (e.g. upcoming meetings) is loaded exclusively by
  # handle_params/3 and does not need to change when an integration is added
  # or removed.
  @spec refresh_dashboard_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp refresh_dashboard_data(socket) do
    if user = socket.assigns[:current_user] do
      DashboardContext.invalidate_integration_status(user.id)
      integration_status = DashboardContext.get_integration_status(user.id)
      assign(socket, :integration_status, integration_status)
    else
      socket
    end
  end

  @spec load_dashboard_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  defp load_dashboard_data(socket) do
    user = socket.assigns[:current_user]
    action = socket.assigns[:live_action]
    timezone = socket.assigns[:profile] && socket.assigns.profile.timezone

    if user do
      dashboard_data = DashboardContext.get_dashboard_data_for_action(user, timezone, action)
      assign(socket, dashboard_data)
    else
      socket
    end
  end

  # Rebuilds only the agenda on a tick; a stale timer that fires after the
  # user has navigated elsewhere is a no-op.
  defp refresh_agenda(%{assigns: %{live_action: action}} = socket)
       when action in [:overview, :calendar],
       do: load_dashboard_data(socket)

  defp refresh_agenda(socket), do: socket

  # The Up-next strip and the overview agenda run their own query rather than
  # reading the grid's events, so a mutation the grid applies to itself leaves
  # them showing the old answer until the next tick — an event deleted from the
  # grid stayed advertised above it for up to a minute. Wrapped around every
  # result that can add, move, or remove an entry, including the failure paths:
  # a rebuild costs one read and is a no-op off the two agenda-bearing actions,
  # which is cheaper than reasoning per-handler about which outcomes changed
  # what.
  defp rebuild_agenda({:noreply, socket}), do: {:noreply, refresh_agenda(socket)}
end
