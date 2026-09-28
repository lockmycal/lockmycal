defmodule Tymeslot.Integrations.Calendar.ConnectionLimitTest do
  @moduledoc """
  The per-user calendar connection limit: `Calendar.connection_limit/1`, the
  up-front refusal in the creation pipelines, and the insert-time enforcement
  in `PrimarySelection.create_with_auto_primary/1` that every creation path
  (forms, subscriptions, Exchange, OAuth) ends in.
  """

  use Tymeslot.DataCase, async: false

  @moduletag :integrations
  @moduletag :calendar

  import Mox
  import Tymeslot.ConfigTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Integrations.Calendar.CalendarIntegrationQueries
  alias Tymeslot.Integrations.Calendar.PrimarySelection

  setup :verify_on_exit!

  defmodule LimitOneChecker do
    @moduledoc false
    @behaviour Tymeslot.Features.CheckerBehaviour

    @impl Tymeslot.Features.CheckerBehaviour
    def check_access(_user_id, _feature), do: :ok

    @impl Tymeslot.Features.CheckerBehaviour
    def limit(_user_id, :calendar_integrations), do: 1
    def limit(_user_id, _resource), do: :unlimited
  end

  defp caldav_attrs(user) do
    %{
      user_id: user.id,
      name: "Work",
      provider: "caldav",
      base_url: "https://caldav.example.com",
      username: "someone",
      password: "secret",
      calendar_paths: ["/calendars/someone/work/"],
      provider_account_id: "https://caldav.example.com||someone-#{System.unique_integer()}",
      is_active: true
    }
  end

  describe "with Core's default checker" do
    test "there is no limit" do
      user = insert(:user)
      insert(:calendar_integration, user: user)

      assert %{
               count: 1,
               active: 1,
               limit: :unlimited,
               reached?: false,
               activation_reached?: false
             } =
               Calendar.connection_limit(user.id)

      assert :ok = Calendar.check_connection_limit(user.id)
      assert {:ok, _integration} = PrimarySelection.create_with_auto_primary(caldav_attrs(user))
    end
  end

  describe "with a checker limiting connections to one" do
    setup do
      with_config(:tymeslot, :feature_access_checker, LimitOneChecker)
      :ok
    end

    test "the first connection is allowed" do
      user = insert(:user)
      insert(:profile, user: user)

      assert %{count: 0, limit: 1, reached?: false} = Calendar.connection_limit(user.id)
      assert {:ok, _integration} = PrimarySelection.create_with_auto_primary(caldav_attrs(user))
      assert %{count: 1, reached?: true} = Calendar.connection_limit(user.id)
    end

    test "a connection past the limit is refused and nothing is written" do
      user = insert(:user)
      insert(:calendar_integration, user: user)

      assert {:error, :calendar_limit_reached} = Calendar.check_connection_limit(user.id)

      assert {:error, :calendar_limit_reached} =
               PrimarySelection.create_with_auto_primary(caldav_attrs(user))

      assert CalendarIntegrationQueries.count_for_user(user.id) == 1
    end

    test "a paused integration still counts towards connecting, not towards activating" do
      user = insert(:user)
      insert(:calendar_integration, user: user, is_active: false)

      assert %{count: 1, active: 0, reached?: true, activation_reached?: false} =
               Calendar.connection_limit(user.id)

      assert Calendar.may_activate?(user.id)
    end

    test "another user's integrations don't count" do
      user = insert(:user)
      insert(:calendar_integration)

      assert %{count: 0, reached?: false} = Calendar.connection_limit(user.id)
    end

    test "a subscription is refused before its feed is fetched" do
      user = insert(:user)
      insert(:calendar_integration, user: user)

      # No HTTPClientMock expectation: the probe must never run.
      assert {:error, :calendar_limit_reached} =
               Calendar.create_subscription_with_validation(
                 user.id,
                 %{"name" => "Feed", "url" => "https://example.com/calendar.ics"},
                 []
               )
    end
  end

  describe "activating under a limit of one" do
    setup do
      with_config(:tymeslot, :feature_access_checker, LimitOneChecker)
      user = insert(:user)
      insert(:profile, user: user)
      {:ok, user: user}
    end

    test "a paused integration can't be turned on while another is active", %{user: user} do
      insert(:calendar_integration, user: user)
      paused = insert(:calendar_integration, user: user, is_active: false)

      refute Calendar.may_activate?(user.id)

      assert {:error, :calendar_limit_reached} = Calendar.toggle_integration(paused.id, user.id)
      assert CalendarIntegrationQueries.count_active_for_user(user.id) == 1
    end

    test "pausing is always allowed and frees the slot", %{user: user} do
      active = insert(:calendar_integration, user: user)
      paused = insert(:calendar_integration, user: user, is_active: false)

      assert {:ok, %{is_active: false}} = Calendar.toggle_integration(active.id, user.id)
      assert {:ok, %{is_active: true}} = Calendar.toggle_integration(paused.id, user.id)
    end
  end

  describe "deactivate_over_limit/1" do
    defmodule LimitTwoChecker do
      @moduledoc false
      @behaviour Tymeslot.Features.CheckerBehaviour

      @impl Tymeslot.Features.CheckerBehaviour
      def check_access(_user_id, _feature), do: :ok

      @impl Tymeslot.Features.CheckerBehaviour
      def limit(_user_id, :calendar_integrations), do: 2
      def limit(_user_id, _resource), do: :unlimited
    end

    defp integration_at(user, days_ago, attrs \\ []) do
      inserted_at = DateTime.add(DateTime.utc_now(:second), -days_ago, :day)
      insert(:calendar_integration, [user: user, inserted_at: inserted_at] ++ attrs)
    end

    test "keeps the primary and the oldest active, pauses the rest" do
      with_config(:tymeslot, :feature_access_checker, LimitTwoChecker)
      user = insert(:user)
      oldest = integration_at(user, 30)
      _second = integration_at(user, 20)
      newest_primary = integration_at(user, 1)
      _newer = integration_at(user, 5)
      already_paused = integration_at(user, 40, is_active: false)
      insert(:profile, user: user, primary_calendar_integration_id: newest_primary.id)

      assert {:ok, paused_ids} = Calendar.deactivate_over_limit(user.id)

      active_ids =
        user.id |> CalendarIntegrationQueries.list_active_for_user() |> Enum.map(& &1.id)

      assert Enum.sort(active_ids) == Enum.sort([newest_primary.id, oldest.id])
      assert length(paused_ids) == 2
      refute already_paused.id in paused_ids
    end

    test "does nothing without a limit" do
      user = insert(:user)
      insert(:calendar_integration, user: user)
      insert(:calendar_integration, user: user)

      assert {:ok, []} = Calendar.deactivate_over_limit(user.id)
      assert CalendarIntegrationQueries.count_active_for_user(user.id) == 2
    end

    test "does nothing when already within the limit" do
      with_config(:tymeslot, :feature_access_checker, LimitTwoChecker)
      user = insert(:user)
      insert(:calendar_integration, user: user)

      assert {:ok, []} = Calendar.deactivate_over_limit(user.id)
    end
  end
end
