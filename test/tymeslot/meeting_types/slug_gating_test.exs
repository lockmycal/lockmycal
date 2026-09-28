defmodule Tymeslot.MeetingTypes.SlugGatingTest do
  @moduledoc """
  Verifies `:custom_booking_link_allowed` gating on the real write path for a
  meeting type's custom slug — `Tymeslot.MeetingTypes.Slugs.update_slug/2`.
  Core always allows (`Tymeslot.Features.DefaultAccessChecker`); a SaaS
  overlay restricts this to Pro plans by swapping the configured
  `:feature_access_checker`, same pattern as
  `test/tymeslot/profiles/username_gating_test.exs`.
  """

  # async: false — mutates the global :feature_access_checker application env,
  # same reasoning as test/tymeslot/profiles/username_gating_test.exs.
  use Tymeslot.DataCase, async: false

  @moduletag :meeting_types
  @moduletag :database

  alias Tymeslot.MeetingTypes.MeetingTypeQueries
  alias Tymeslot.MeetingTypes.Slugs

  setup do
    previous_checker = Application.get_env(:tymeslot, :feature_access_checker)

    on_exit(fn ->
      Application.put_env(:tymeslot, :feature_access_checker, previous_checker)
    end)

    :ok
  end

  defp deny_custom_booking_link do
    Application.put_env(
      :tymeslot,
      :feature_access_checker,
      Tymeslot.MeetingTypes.SlugGatingTest.DenyAccessChecker
    )
  end

  describe "Slugs.update_slug/2" do
    test "succeeds when the feature checker allows it (Core default)" do
      user = insert(:user)
      meeting_type = insert(:meeting_type, user: user)
      new_slug = "allowed-#{System.unique_integer([:positive])}"

      assert {:ok, updated} = Slugs.update_slug(meeting_type, new_slug)
      assert updated.slug == new_slug
    end

    test "is rejected, and nothing is persisted, when the feature checker denies it" do
      user = insert(:user)
      meeting_type = insert(:meeting_type, user: user, slug: "original-slug")
      deny_custom_booking_link()

      assert {:error, :insufficient_plan} =
               Slugs.update_slug(meeting_type, "attempted-change")

      reloaded = MeetingTypeQueries.get_meeting_type(meeting_type.id, user.id)
      assert reloaded.slug == "original-slug"
    end
  end

  describe "Slugs.reset_slug/1" do
    test "clears the slug even when the feature checker denies :custom_booking_link_allowed" do
      user = insert(:user)
      meeting_type = insert(:meeting_type, user: user, slug: "original-slug")
      deny_custom_booking_link()

      assert {:ok, updated} = Slugs.reset_slug(meeting_type)
      assert updated.slug == nil
    end
  end
end

defmodule Tymeslot.MeetingTypes.SlugGatingTest.DenyAccessChecker do
  @moduledoc false

  @spec check_access(any(), atom()) :: :ok | {:error, :insufficient_plan}
  def check_access(_user_id, :custom_booking_link_allowed), do: {:error, :insufficient_plan}
  def check_access(_user_id, _feature), do: :ok
end
