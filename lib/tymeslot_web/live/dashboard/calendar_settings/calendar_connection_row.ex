defmodule TymeslotWeb.Dashboard.CalendarSettings.CalendarConnectionRow do
  @moduledoc """
  Renders a connected calendar integration as a shared `ConnectionRow`, and
  builds the one-line human summary shown inside it.

  Split out of `TymeslotWeb.Dashboard.CalendarSettings.Components` (which
  still owns `config_view`/`freebusy_section`/`connected_calendars_section`)
  as this row's own self-contained rendering and summary-building concern.
  """
  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.BookingEligibility
  alias Tymeslot.Integrations.Calendar.DisplayHelpers
  alias Tymeslot.Integrations.Calendar.ProviderConfig
  alias Tymeslot.Integrations.Calendar.TokenUtils
  alias Tymeslot.Integrations.HealthCheck
  alias TymeslotWeb.Components.Dashboard.Integrations.Shared.ConnectionRow
  alias TymeslotWeb.Dashboard.CalendarSettings.Helpers

  @doc """
  Renders a single connected calendar integration as a shared
  `connection_row`: a status-first, flat row with a one-line summary and an
  always-visible action cluster — Upgrade (Google scope, when needed), Manage
  calendars (opens the selection modal), Reconnect (promoted when the
  integration needs re-authentication), and a Delete icon. There is no
  expand/collapse; every action is one click away.
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
    calendar_list = integration.calendar_list || []

    # Two distinct questions: a subscribed feed carries no credentials and
    # exactly one calendar, so it gets neither the reconnect nor the
    # manage-calendars action, and it is also the one provider that is
    # read-only by construction, which is what the badge states.
    subscription? = ProviderConfig.subscription?(integration.provider)
    read_only? = ProviderConfig.read_only?(integration.provider)

    assigns =
      assigns
      |> assign(:calendar_list, calendar_list)
      |> assign(:status, integration_status(integration, assigns.health_state))
      |> assign(:summary, calendar_summary(integration))
      |> assign(:subscription?, subscription?)
      |> assign(:read_only?, read_only?)
      |> assign(
        :display_name,
        if(integration.name == provider_name, do: provider_name, else: integration.name)
      )

    ~H"""
    <ConnectionRow.connection_row
      id={to_string(@integration.id)}
      icon={@integration.provider}
      icon_type={:calendar}
      title={@display_name}
      type_tag={if @read_only?, do: dgettext("dashboard_calendar_settings", "Read-only")}
      summary={@summary}
      notice={ConnectionRow.reconnect_reason(@integration)}
      status={@status}
      active?={@integration.is_active}
      toggle_event="toggle_integration"
      toggle_disabled={@activation_blocked and not @integration.is_active}
      myself={@myself}
    >
      <:actions>
        <button
          :if={@integration.provider == "google" && Helpers.needs_scope_upgrade?(@integration)}
          phx-click="upgrade_google_scope"
          phx-value-id={@integration.id}
          phx-target={@myself}
          class="row-action-button row-action-button--pill row-action-button--attention"
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
          class="row-action-button row-action-button--pill row-action-button--neutral"
          title={
            dgettext(
              "dashboard_calendar_settings",
              "Rename, recolour, and choose which calendars sync"
            )
          }
          aria-label={dgettext("dashboard_calendar_settings", "Manage calendars")}
        >
          <.icon name="hero-squares-2x2" class="w-4 h-4" /><span class="lg:hidden">{dgettext(
            "dashboard_calendar_settings",
            "Manage calendars"
          )}</span>
        </button>
        <%!-- A subscription has no credentials to re-enter, only a feed URL
        that can go stale (rotated or revoked) — CaldavReconnectModal handles
        it too, with its username/password fields made optional for it. --%>
        <.reconnect_button
          provider={@integration.provider}
          integration_id={@integration.id}
          myself={@myself}
          variant={(@integration.needs_reauth && :attention) || :normal}
        />
        <button
          phx-click="show"
          phx-value-id={@integration.id}
          phx-target="#delete-calendar-modal"
          class="row-action-button row-action-button--danger"
          title={dgettext("dashboard_calendar_settings", "Remove connection")}
          aria-label={dgettext("dashboard_calendar_settings", "Remove connection")}
        >
          <.icon name="hero-trash" class="w-5 h-5" />
        </button>
      </:actions>
    </ConnectionRow.connection_row>
    """
  end

  # Always-visible reconnect control: oauth providers re-trigger
  # `connect_provider`, everything else opens the CalDAV reconnect modal.
  # `:attention` is the promoted (amber) style used when the integration needs
  # re-authentication; `:normal` is the subtle default.
  attr :provider, :string, required: true
  attr :integration_id, :any, required: true
  attr :myself, :any, required: true
  attr :variant, :atom, values: [:normal, :attention], required: true

  defp reconnect_button(assigns) do
    assigns = assign(assigns, :class, reconnect_button_class(assigns.variant))

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
      <.icon name="hero-arrow-path" class="w-4 h-4" /><span class="lg:hidden">{dgettext(
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
      <.icon name="hero-arrow-path" class="w-4 h-4" /><span class="lg:hidden">{dgettext(
        "dashboard_calendar_settings",
        "Reconnect"
      )}</span>
    </button>
    """
  end

  # Full padded pill on mobile, compact icon-only square on desktop (the
  # label collapses via `lg:hidden`). Only the colour palette differs
  # between the promoted (:attention) and subtle (:normal) variants.
  defp reconnect_button_class(:attention),
    do: "row-action-button row-action-button--pill row-action-button--attention"

  defp reconnect_button_class(:normal),
    do: "row-action-button row-action-button--pill row-action-button--neutral"

  @doc """
  Builds a one-line human summary for a calendar integration — account
  email, conflict-check coverage, booking target, and last-sync — dropping
  absent segments gracefully.

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
        ConnectionRow.server_label(Map.get(integration, :base_url)),
      conflict_segment(integration, calendar_list),
      booking_segment(integration),
      sync_segment(integration)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  # Status-first badge mapping. Precedence lives in the canonical
  # `HealthCheck.attention_status/2` classifier; this just maps the atom to
  # this row's badge variant/label.
  defp integration_status(integration, health) do
    case HealthCheck.attention_status(integration, health) do
      :paused -> {:paused, dgettext("dashboard_calendar_settings", "Paused")}
      :needs_reauth -> {:warning, dgettext("dashboard_calendar_settings", "Reconnect")}
      :unhealthy -> {:warning, dgettext("dashboard_calendar_settings", "Connection issues")}
      :ok -> {:ok, dgettext("dashboard_calendar_settings", "Healthy")}
    end
  end

  defp conflict_segment(%{is_active: true}, calendar_list) when calendar_list != [] do
    selected = Enum.count(calendar_list, & &1.selected)

    dgettext("dashboard_calendar_settings", "conflict-checks %{selected} of %{total} calendars",
      selected: selected,
      total: length(calendar_list)
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
        if BookingEligibility.bookable?(integration), do: nil, else: feed_segment()
    end
  end

  # Two situations, two sentences, and the provider is what tells them apart.
  # A provider that is read-only by construction gets a plain description: a
  # subscribed feed blocks time and never takes bookings, which is how it has
  # always behaved and is nothing to fix. The
  # warning below says "no longer", which is the right thing to tell someone
  # whose writable calendar has become read-only on the server and whose
  # bookings are now failing; saying it about a feed would report a breakage
  # where nothing has changed and nothing is wrong.
  defp read_only_target_segment(integration) do
    if BookingEligibility.bookable?(integration) do
      dgettext("dashboard_calendar_settings", "booking target can no longer accept bookings")
    else
      feed_segment()
    end
  end

  defp feed_segment,
    do: dgettext("dashboard_calendar_settings", "read-only, blocks time but takes no bookings")

  # `last_external_sync_at` is what every sync worker stamps and what the
  # staleness banner reads. This used to read a second, never-written column
  # instead, which silently dropped the segment for every integration; that
  # column has since been dropped so the mistake cannot be made again.
  defp sync_segment(%{last_external_sync_at: %DateTime{} = synced_at}),
    do:
      dgettext("dashboard_calendar_settings", "synced %{time}",
        time: TokenUtils.relative_time(synced_at)
      )

  defp sync_segment(_integration), do: nil
end
