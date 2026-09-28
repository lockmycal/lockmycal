defmodule Tymeslot.Profiles.UsernameGatingTest do
  @moduledoc """
  Verifies `:custom_username_allowed` gating on the two real write paths for a
  profile's username — `Profiles.update_username/3` (dashboard) and
  `Profiles.Settings.update_basic_settings/3` (onboarding). Core always allows
  (`Tymeslot.Features.DefaultAccessChecker`); a SaaS overlay restricts this to
  Pro plans by swapping the configured `:feature_access_checker`, same pattern
  `Tymeslot.Contacts` and `Tymeslot.Slack` already rely on.
  """

  # async: false — mutates the global :feature_access_checker application env,
  # same reasoning as test/tymeslot/meeting_payments/checkout_sessions_test.exs.
  use Tymeslot.DataCase, async: false

  @moduletag :profiles
  @moduletag :database

  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Profiles.Settings

  setup do
    previous_checker = Application.get_env(:tymeslot, :feature_access_checker)

    on_exit(fn ->
      Application.put_env(:tymeslot, :feature_access_checker, previous_checker)
    end)

    :ok
  end

  defp deny_custom_username do
    Application.put_env(
      :tymeslot,
      :feature_access_checker,
      Tymeslot.Profiles.UsernameGatingTest.DenyAccessChecker
    )
  end

  describe "Profiles.update_username/3" do
    test "succeeds when the feature checker allows it (Core default)" do
      user = insert(:user)
      profile = insert(:profile, user: user)
      new_username = "allowed#{System.unique_integer([:positive])}"

      assert {:ok, updated} = Profiles.update_username(profile, new_username, user.id)
      assert updated.username == new_username
    end

    test "is rejected, and nothing is persisted, when the feature checker denies it" do
      user = insert(:user)
      profile = insert(:profile, user: user, username: "original")
      deny_custom_username()

      assert {:error, :insufficient_plan} =
               Profiles.update_username(profile, "attempted-change", user.id)

      {:ok, reloaded} = ProfileQueries.get_by_user_id(user.id)
      assert reloaded.username == "original"
    end
  end

  describe "Profiles.Settings.update_basic_settings/3" do
    test "applies a requested username change when the feature checker allows it" do
      user = insert(:user)
      profile = insert(:profile, user: user, username: "original")

      assert {:ok, updated} =
               Settings.update_basic_settings(profile, %{
                 "full_name" => "New Name",
                 "username" => "requested"
               })

      assert updated.username == "requested"
      assert updated.full_name == "New Name"
    end

    test "silently keeps the existing username, but still saves other fields, when denied" do
      user = insert(:user)
      profile = insert(:profile, user: user, username: "locked-in")
      deny_custom_username()

      assert {:ok, updated} =
               Settings.update_basic_settings(profile, %{
                 "full_name" => "New Name",
                 "username" => "attempted-change"
               })

      assert updated.username == "locked-in"
      assert updated.full_name == "New Name"
    end
  end

  describe "Profiles.generate_locked_username/1" do
    test "produces a unique, cryptographically random, format-valid username" do
      user = insert(:user)

      username = Profiles.generate_locked_username(user.id)

      # Format-valid and not the predictable "user_<id>" shape
      # generate_default_username/1 produces — a locked user's link must
      # not be enumerable from their user_id.
      assert username =~ ~r/\Acalendar-[a-f0-9]{10}\z/
      assert Profiles.username_available?(username)
    end

    test "produces different tokens across calls" do
      user = insert(:user)

      assert Profiles.generate_locked_username(user.id) !=
               Profiles.generate_locked_username(user.id)
    end
  end
end

defmodule Tymeslot.Profiles.UsernameGatingTest.DenyAccessChecker do
  @moduledoc false

  @spec check_access(any(), atom()) :: :ok | {:error, :insufficient_plan}
  def check_access(_user_id, :custom_username_allowed), do: {:error, :insufficient_plan}
  def check_access(_user_id, _feature), do: :ok
end
