defmodule Tymeslot.Integrations.Calendar.ColourOverrideDurabilityTest do
  @moduledoc """
  Regression guard for the "separate override table" design decision: the durable
  override must survive a full provider re-sync (prune + re-upsert of the cache
  row), where a colour column on the cache row would be overwritten.
  """
  use Tymeslot.DataCase, async: true

  @moduletag :calendar

  alias Tymeslot.Integrations.Calendar.EventColourOverrides
  alias Tymeslot.Integrations.Calendar.ProviderCalendarEventQueries

  defp insert_cached(integration, start_at) do
    insert(:provider_calendar_event,
      calendar_integration: integration,
      summary: "Sync me",
      uid: "uid-dur",
      colour: "blueberry",
      all_day: false,
      start_at: start_at,
      end_at: DateTime.add(start_at, 3600, :second)
    )
  end

  test "override survives a full cache re-sync" do
    user = insert(:user)
    integration = insert(:calendar_integration, user: user)
    start_at = DateTime.new!(Date.add(Date.utc_today(), 1), ~T[13:00:00], "Etc/UTC")

    insert_cached(integration, start_at)

    {:ok, _override} =
      EventColourOverrides.set(user.id, {:external, integration.id, "uid-dur"}, "tomato")

    # Simulate a full re-sync: prune the cache row, then re-insert it from provider
    # data (whose colour is the provider's value, "blueberry", not the override).
    ProviderCalendarEventQueries.delete_by_uid(integration.id, "uid-dur")
    insert_cached(integration, start_at)

    # The override is untouched by the cache churn.
    assert EventColourOverrides.overrides_for(user.id) ==
             %{{:external, integration.id, "uid-dur"} => "tomato"}
  end
end
