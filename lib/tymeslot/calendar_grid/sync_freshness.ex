defmodule Tymeslot.CalendarGrid.SyncFreshness do
  @moduledoc """
  How fresh the calendar grid's cached events are: which integrations have
  not synced within their provider's expected interval, and the oldest and
  most recent sync across a set of integrations. Called through
  `Tymeslot.CalendarGrid`.
  """

  alias Tymeslot.Integrations.Calendar.CalendarIntegrationSchema
  alias Tymeslot.Integrations.Calendar.ProviderConfig

  # Staleness thresholds (minutes). Each threshold is the sync interval
  # plus a buffer for queue wait, network latency, and retries.
  @webhook_stale_minutes 30
  @caldav_tier_stale_minutes %{
    1 => 25,
    2 => 45,
    3 => 90
  }
  @caldav_default_stale_minutes 25
  @debug_stale_minutes 15
  # Subscriptions are swept every 30 minutes; the buffer is wider than the
  # CalDAV ones because the publisher's own regeneration schedule sits on top
  # of ours, so a feed being an hour old is normal rather than a symptom.
  @subscription_stale_minutes 75
  # Exchange is swept on the same 30-minute cadence as a subscription, and for
  # the same reason: no delta mechanism, so every run re-reads the whole
  # window twice over. The buffer is the sweep interval plus queue wait.
  @exchange_stale_minutes 45

  @doc """
  Returns integrations whose cached data is stale.

  An integration is stale when `last_external_sync_at` is nil or older than the
  provider-appropriate threshold:
  - Webhook providers (Google, Outlook): #{@webhook_stale_minutes} min
  - CalDAV Tier 1 (sync-token, syncs every 15 min): #{@caldav_tier_stale_minutes[1]} min
  - CalDAV Tier 2 (CTag, syncs every 30 min): #{@caldav_tier_stale_minutes[2]} min
  - CalDAV Tier 3 (full fetch, syncs every 60 min): #{@caldav_tier_stale_minutes[3]} min
  - Calendar subscriptions (full fetch, syncs every 30 min): #{@subscription_stale_minutes} min
  """
  @spec stale_integrations([CalendarIntegrationSchema.t()]) :: [CalendarIntegrationSchema.t()]
  def stale_integrations(integrations) do
    now = DateTime.utc_now()
    Enum.filter(integrations, &stale?(&1, now))
  end

  @doc """
  Returns the oldest `last_external_sync_at` across the given integrations,
  or nil when none have synced.
  """
  @spec oldest_sync_at([CalendarIntegrationSchema.t()]) :: DateTime.t() | nil
  def oldest_sync_at([]), do: nil

  def oldest_sync_at(integrations) do
    timestamps =
      integrations
      |> Enum.map(& &1.last_external_sync_at)
      |> Enum.reject(&is_nil/1)

    if timestamps == [], do: nil, else: Enum.min(timestamps, DateTime)
  end

  @doc """
  Returns the most recent `last_external_sync_at` across the given
  integrations, or nil when none have synced yet. Used for the toolbar's
  routine "last synced" indicator — unlike `oldest_sync_at/1`, which flags
  the worst-case staleness, this reports how fresh the grid's data is
  overall.
  """
  @spec most_recent_sync_at([CalendarIntegrationSchema.t()]) :: DateTime.t() | nil
  def most_recent_sync_at([]), do: nil

  def most_recent_sync_at(integrations) do
    timestamps =
      integrations
      |> Enum.map(& &1.last_external_sync_at)
      |> Enum.reject(&is_nil/1)

    if timestamps == [], do: nil, else: Enum.max(timestamps, DateTime)
  end

  # Outlook pending initial setup: subscription registration hasn't succeeded yet
  # (e.g. WEBHOOK_BASE_URL not configured). This is "pending", not "stale" —
  # showing a stale banner the user can't resolve is just noise.
  defp stale?(%{provider: "outlook", graph_delta_link: nil, last_external_sync_at: nil}, _now),
    do: false

  defp stale?(%{last_external_sync_at: nil}, _now), do: true

  defp stale?(integration, now) do
    threshold = stale_threshold_minutes(integration)
    cutoff = DateTime.add(now, -threshold, :minute)
    DateTime.before?(integration.last_external_sync_at, cutoff)
  end

  defp stale_threshold_minutes(%{provider: "debug"}), do: @debug_stale_minutes

  defp stale_threshold_minutes(%{provider: "ics_url"}), do: @subscription_stale_minutes

  defp stale_threshold_minutes(%{provider: "exchange"}), do: @exchange_stale_minutes

  # The CalDAV provider list is read at run time rather than into a module
  # attribute for a guard, which would make this module a compile-time
  # dependant of ProviderConfig.
  defp stale_threshold_minutes(%{provider: provider, caldav_sync_tier: tier}) do
    if provider in ProviderConfig.caldav_based_provider_strings(),
      do: Map.get(@caldav_tier_stale_minutes, tier, @caldav_default_stale_minutes),
      else: @webhook_stale_minutes
  end

  defp stale_threshold_minutes(_integration), do: @webhook_stale_minutes
end
