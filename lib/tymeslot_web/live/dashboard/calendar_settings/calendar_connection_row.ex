defmodule TymeslotWeb.Dashboard.CalendarSettings.CalendarConnectionRow do
  @moduledoc """
  Renders a connected calendar integration as a shared `integration_card`, and
  builds the one-line human summary shown inside it.

  Upstream renders this card inside `CalendarSettings.Components`; the fork
  keeps it in its own module because it adds the default-calendar controls,
  the registered connection tags and the active-calendar limit on top.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Dashboard.CalendarConnectionTag
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.BookingEligibility
  alias Tymeslot.Integrations.Calendar.DisplayHelpers
  alias Tymeslot.Integrations.Calendar.ProviderConfig
  alias Tymeslot.Integrations.Calendar.TokenUtils
  alias Tymeslot.Integrations.HealthCheck
  alias TymeslotWeb.Components.Dashboard.Integrations.Shared.ConnectionLabels
  alias TymeslotWeb.Components.Dashboard.Integrations.Shared.IntegrationCard
  alias TymeslotWeb.Components.Icons.ProviderIcon
  alias TymeslotWeb.Dashboard.CalendarSettings.Helpers

  @doc """
  Renders a single connected calendar integration as a shared
  `integration_card`: a status-first card with a one-line summary and an
  always-visible action bar: the default-calendar star, Upgrade (Google scope,
  when needed), Manage calendars (opens the selection modal), Reconnect
  (promoted when the integration needs re-authentication), and a Delete icon.
  There is no expand/collapse; every action is one click away.
  """
  attr :integration, :map, required: true
  attr :myself, :any, required: true
  attr :health_state, :map, default: nil

  attr :activation_blocked, :boolean,
    default: false,
    doc: "the user is at their active-calendar limit, so a paused row can't be switched on"

  @spec calendar_connection_row(map()) :: Phoenix.LiveView.Rendered.t()
  def calendar_connection_row(assigns) do
    integration = assigns.integration
    provider_name = Helpers.format_provider_name(integration.provider)

    assigns =
      assigns
      |> assign(:primary?, Map.get(integration, :is_primary, false))
      |> assign(:default_calendar, default_calendar(integration))
      |> assign(
        :choose_default_calendar?,
        Map.get(integration, :is_primary, false) and can_become_default?(integration)
      )
      |> assign(:status, integration_status(integration, assigns.health_state))
      |> assign(:summary, calendar_summary(integration))
      |> assign(:last_synced, last_synced(integration))
      |> assign(:subscription?, ProviderConfig.subscription?(integration.provider))
      |> assign(:all_events_busy?, Map.get(integration, :all_events_busy, false))
      |> assign(
        :type_tag,
        if(ProviderConfig.read_only?(integration.provider),
          do: dgettext("dashboard_calendar_settings", "Read-only"),
          else: CalendarConnectionTag.for_integration(integration)
        )
      )
      |> assign(
        :display_name,
        if(integration.name == provider_name, do: provider_name, else: integration.name)
      )

    ~H"""
    <IntegrationCard.integration_card
      id={to_string(@integration.id)}
      title={@display_name}
      type_tag={@type_tag}
      summary={@summary}
      notice={ConnectionLabels.reconnect_reason(@integration)}
      status={@status}
      active={@integration.is_active}
      toggle_event="toggle_integration"
      toggle_disabled={@activation_blocked and not @integration.is_active}
      target={@myself}
    >
      <:icon>
        <ProviderIcon.provider_icon
          provider={@integration.provider}
          type="calendar"
          size="medium"
          alt=""
        />
      </:icon>
      <:title_badges>
        <%!-- On a default connection with several calendars the badge is the
             control that picks which of them is the default; the star in the
             footer only marks the connection as the default. --%>
        <button
          :if={@choose_default_calendar?}
          type="button"
          phx-click="show"
          phx-value-id={@integration.id}
          phx-target="#default-calendar-modal"
          class={[
            default_badge_class(),
            "cursor-pointer hover:bg-primary-100 dark:hover:bg-primary-900 focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-primary-400"
          ]}
          title={default_action_label(@integration)}
          data-testid="default-calendar-badge"
        >
          {default_badge_label(@default_calendar)}
        </button>
        <span
          :if={@primary? and not @choose_default_calendar?}
          class={default_badge_class()}
          title={
            dgettext(
              "dashboard_calendar_settings",
              "Bookings without a calendar of their own, and your bookings on other pages, go here"
            )
          }
          data-testid="default-calendar-badge"
        >
          {default_badge_label(@default_calendar)}
        </span>
      </:title_badges>
      <:last_activity :if={@last_synced}>{@last_synced}</:last_activity>
      <:actions>
        <button
          :if={@primary?}
          type="button"
          disabled
          class={tile_class(:neutral)}
          title={dgettext("dashboard_calendar_settings", "Default calendar")}
          aria-label={dgettext("dashboard_calendar_settings", "Default calendar")}
          aria-pressed="true"
          data-testid="default-calendar-star"
        >
          <.icon name="hero-star-solid" class="w-4 h-4 text-primary-500" /><span class="max-sm:sr-only">{dgettext(
            "dashboard_calendar_settings",
            "Default calendar"
          )}</span>
        </button>
        <button
          :if={not @primary? and can_become_default?(@integration)}
          type="button"
          phx-click="show"
          phx-value-id={@integration.id}
          phx-target="#default-calendar-modal"
          class={tile_class(:neutral)}
          title={default_action_label(@integration)}
          aria-label={default_action_label(@integration)}
          data-testid="set-default-calendar"
        >
          <.icon name="hero-star" class="w-4 h-4" /><span class="max-sm:sr-only">{default_action_label(
            @integration
          )}</span>
        </button>
        <button
          :if={@integration.provider == "google" && Helpers.needs_scope_upgrade?(@integration)}
          phx-click="upgrade_google_scope"
          phx-value-id={@integration.id}
          phx-target={@myself}
          class={tile_class(:warning)}
          title={dgettext("dashboard_calendar_settings", "Upgrade Google Calendar permissions")}
        >
          <.icon name="hero-bolt" class="w-4 h-4" /> {dgettext(
            "dashboard_calendar_settings",
            "Upgrade"
          )}
        </button>
        <%!-- Shown even when no calendars have been discovered yet: the modal
             also carries the name and colour, which apply to any connection.
             A subscription always has exactly one calendar, always selected,
             so the modal hides the calendar-selection grid for it and keeps
             only rename + colour (see CalendarSelectionModal). --%>
        <button
          phx-click="manage_calendars"
          phx-value-id={@integration.id}
          phx-target={@myself}
          class={tile_class(:neutral)}
          title={
            dgettext(
              "dashboard_calendar_settings",
              "Rename, recolour, and choose which calendars sync"
            )
          }
          aria-label={dgettext("dashboard_calendar_settings", "Manage calendars")}
        >
          <.icon name="hero-squares-2x2" class="w-4 h-4" /><span>{dgettext(
            "dashboard_calendar_settings",
            "Manage calendars"
          )}</span>
        </button>
        <%!-- A subscription's one feed setting is a toggle here: whether every
             event in the feed blocks time, also those it marks free (holiday
             feeds mark all of them free). --%>
        <button
          :if={@subscription?}
          type="button"
          phx-click="toggle_all_events_busy"
          phx-value-id={@integration.id}
          phx-target={@myself}
          class={tile_class(:neutral)}
          aria-pressed={to_string(@all_events_busy?)}
          data-testid="all-events-busy-toggle"
          title={
            dgettext(
              "dashboard_calendar_settings",
              "Block the time of every event in this feed, also those it marks as free"
            )
          }
        >
          <.icon
            name={if @all_events_busy?, do: "hero-check-circle", else: "hero-no-symbol"}
            class="w-4 h-4"
          /><span>{dgettext("dashboard_calendar_settings", "Every event busy")}</span>
        </button>
        <%!-- A subscription has no credentials to re-enter, only a feed URL
        that can go stale (rotated or revoked); CaldavReconnectModal handles
        it too, with its username/password fields made optional for it. --%>
        <.reconnect_button
          provider={@integration.provider}
          integration_id={@integration.id}
          myself={@myself}
          variant={(@integration.needs_reauth && :attention) || :normal}
        />
      </:actions>
      <:end_actions>
        <.icon_button
          icon="hero-trash"
          variant={:danger}
          label={dgettext("dashboard_calendar_settings", "Delete %{name}", name: @display_name)}
          tooltip={dgettext("dashboard_calendar_settings", "Delete")}
          phx-click="show"
          phx-value-id={@integration.id}
          phx-target="#delete-calendar-modal"
        />
      </:end_actions>
    </IntegrationCard.integration_card>
    """
  end

  # Only a connection that can take a booking can be the default: it is where
  # bookings are written (`CalendarPrimary.set_default_calendar/3` refuses any
  # other). The default one keeps the action (on its badge) while it has
  # several calendars, to change which of them is the default.
  defp can_become_default?(integration) do
    integration.is_active and not integration.needs_reauth and
      BookingEligibility.bookable?(integration) and
      (not Map.get(integration, :is_primary, false) or several_calendars?(integration))
  end

  defp default_action_label(integration) do
    if Map.get(integration, :is_primary, false),
      do: dgettext("dashboard_calendar_settings", "Change default calendar"),
      else: dgettext("dashboard_calendar_settings", "Set as default")
  end

  defp default_badge_class,
    do:
      "rounded-token-sm bg-primary-50 px-1.5 py-0.5 text-token-xs font-semibold uppercase text-primary-700 dark:bg-primary-950/40 dark:text-primary-200"

  defp default_badge_label(nil), do: dgettext("dashboard_calendar_settings", "Default")

  defp default_badge_label(calendar),
    do: dgettext("dashboard_calendar_settings", "Default: %{calendar}", calendar: calendar)

  defp several_calendars?(integration),
    do: match?([_, _ | _], Calendar.writable_calendars(integration.calendar_list))

  # The calendar picked within the default connection, named on its badge
  # when there was a choice to make.
  defp default_calendar(%{default_calendar_id: id} = integration) when is_binary(id) do
    with true <- several_calendars?(integration),
         %{} = calendar <-
           Enum.find(Calendar.writable_calendars(integration.calendar_list), &(&1.id == id)) do
      calendar.name || calendar.id
    else
      _no_pick -> nil
    end
  end

  defp default_calendar(_integration), do: nil

  # Always-visible reconnect control: oauth providers re-trigger
  # `connect_provider`, everything else opens the CalDAV reconnect modal.
  # `:attention` is the promoted (amber) style used when the integration needs
  # re-authentication; `:normal` is the subtle default.
  attr :provider, :string, required: true
  attr :integration_id, :any, required: true
  attr :myself, :any, required: true
  attr :variant, :atom, values: [:normal, :attention], required: true

  defp reconnect_button(assigns) do
    assigns =
      assign(assigns,
        class: reconnect_button_class(assigns.variant),
        label_class: reconnect_label_class(assigns.variant)
      )

    ~H"""
    <button
      :if={@provider in ["google", "outlook"]}
      phx-click="connect_provider"
      phx-value-provider={@provider}
      phx-target={@myself}
      class={@class}
      title={dgettext("dashboard_calendar_settings", "Reconnect integration")}
      aria-label={dgettext("dashboard_calendar_settings", "Reconnect integration")}
    >
      <.icon name="hero-arrow-path" class="w-4 h-4" /><span class={@label_class}>{dgettext(
        "dashboard_calendar_settings",
        "Reconnect"
      )}</span>
    </button>
    <button
      :if={@provider not in ["google", "outlook"]}
      phx-click="show_reconnect"
      phx-value-id={@integration_id}
      phx-target="#caldav-reconnect-modal"
      class={@class}
      title={dgettext("dashboard_calendar_settings", "Reconnect integration")}
      aria-label={dgettext("dashboard_calendar_settings", "Reconnect integration")}
    >
      <.icon name="hero-arrow-path" class="w-4 h-4" /><span class={@label_class}>{dgettext(
        "dashboard_calendar_settings",
        "Reconnect"
      )}</span>
    </button>
    """
  end

  # The promoted (:attention) style is the amber warning tile; the subtle
  # (:normal) one is the neutral tile.
  defp reconnect_button_class(:attention), do: tile_class(:warning)

  defp reconnect_button_class(:normal),
    do: [tile_class(:neutral), "max-sm:h-9 max-sm:w-9 max-sm:px-0 max-sm:py-0"]

  # On a phone the routine Reconnect shrinks to its icon so the footer's
  # actions share one row; a promoted Reconnect is the action the owner has
  # to take, so it keeps its label there too.
  defp reconnect_label_class(:attention), do: nil
  defp reconnect_label_class(:normal), do: "max-sm:sr-only"

  defp tile_class(variant), do: IntegrationCard.action_tile_class(variant)

  @doc """
  Builds a one-line human summary for a calendar integration: account
  email, conflict-check coverage and booking target, dropping absent segments
  gracefully. When it last synced is the card's last-activity line instead.

  Only the OAuth providers record an account email, so a CalDAV-family row
  names its server instead; without it the line would identify neither the
  account nor the host it belongs to.
  """
  @spec calendar_summary(%{:provider => atom() | String.t() | nil, optional(atom()) => term()}) ::
          String.t()
  def calendar_summary(integration) do
    calendar_list = integration.calendar_list || []

    [
      integration.provider_account_email ||
        ConnectionLabels.server_label(Map.get(integration, :base_url)),
      conflict_segment(integration, calendar_list),
      booking_segment(integration)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  # Status-first badge mapping. Precedence lives in the canonical
  # `HealthCheck.attention_status/2` classifier; this just maps the atom to
  # the card's status tone/label.
  defp integration_status(integration, health) do
    case HealthCheck.attention_status(integration, health) do
      :paused -> {:neutral, dgettext("dashboard_calendar_settings", "Paused")}
      :needs_reauth -> {:warning, dgettext("dashboard_calendar_settings", "Reconnect")}
      :unhealthy -> {:warning, dgettext("dashboard_calendar_settings", "Connection issues")}
      :ok -> {:success, dgettext("dashboard_calendar_settings", "Healthy")}
    end
  end

  defp conflict_segment(%{is_active: true}, calendar_list) when calendar_list != [] do
    selected = Enum.count(calendar_list, & &1.selected)

    dngettext(
      "dashboard_calendar_settings",
      "checks %{selected} of %{count} calendar for conflicts",
      "checks %{selected} of %{count} calendars for conflicts",
      length(calendar_list),
      selected: selected
    )
  end

  defp conflict_segment(_integration, _calendar_list), do: nil

  # This is a display-only summary, so it only names a booking target once one
  # is set; see `Calendar.booking_target/1`, which follows the calendar bookings
  # are actually written to. A read-only target is a problem the user needs to
  # fix, not an absent one, so it is surfaced rather than dropped.
  defp booking_segment(integration) do
    case Calendar.booking_target(integration) do
      {:ok, calendar} ->
        dgettext("dashboard_calendar_settings", "books into %{calendar}",
          calendar: DisplayHelpers.extract_calendar_display_name(calendar)
        )

      {:read_only, _calendar} ->
        read_only_target_segment(integration)

      :none ->
        if BookingEligibility.bookable?(integration), do: nil, else: feed_segment(integration)
    end
  end

  # Two situations, two sentences, and the provider is what tells them apart.
  # A provider that is read-only by construction gets a plain description: a
  # subscribed feed blocks time and never takes bookings, which is how it has
  # always behaved and is nothing to fix. The warning below says "no longer",
  # which is the right thing to tell someone whose writable calendar has
  # become read-only on the server and whose bookings are now failing; saying
  # it about a feed would report a breakage where nothing has changed.
  defp read_only_target_segment(integration) do
    if BookingEligibility.bookable?(integration) do
      dgettext("dashboard_calendar_settings", "booking target can no longer accept bookings")
    else
      feed_segment(integration)
    end
  end

  defp feed_segment(%{all_events_busy: true}),
    do:
      dgettext(
        "dashboard_calendar_settings",
        "read-only, every event blocks time, also those marked free"
      )

  defp feed_segment(_integration),
    do: dgettext("dashboard_calendar_settings", "read-only, blocks time but takes no bookings")

  # The card's last-activity line; nothing for a connection never synced.
  # `last_external_sync_at` is what every sync worker stamps and what the
  # staleness banner reads.
  defp last_synced(%{last_external_sync_at: %DateTime{} = synced_at}),
    do:
      dgettext("dashboard_calendar_settings", "Last synced %{time}",
        time: TokenUtils.relative_time(synced_at)
      )

  defp last_synced(_integration), do: nil
end
