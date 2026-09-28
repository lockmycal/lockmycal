defmodule TymeslotWeb.OnboardingLive.LockedUsernameTest do
  @moduledoc """
  Onboarding profile-step behaviour when `:custom_username_allowed` is
  gated off (SaaS Free plan): the booking link must be shown read-only,
  and its value must be system-generated up front rather than left for
  the user to type.
  """

  # async: false — mutates the global :feature_access_checker application
  # env, same reasoning as test/tymeslot/profiles/username_gating_test.exs.
  use TymeslotWeb.ConnCase, async: false

  @moduletag :onboarding
  @moduletag :live

  import Phoenix.LiveViewTest
  import TymeslotWeb.OnboardingTestHelpers

  alias Tymeslot.Profiles

  setup do
    previous_checker = Application.get_env(:tymeslot, :feature_access_checker)

    Application.put_env(
      :tymeslot,
      :feature_access_checker,
      TymeslotWeb.OnboardingLive.LockedUsernameTest.DenyAccessChecker
    )

    on_exit(fn ->
      Application.put_env(:tymeslot, :feature_access_checker, previous_checker)
    end)

    :ok
  end

  test "profile step shows a disabled, read-only link pre-filled with a locked username",
       %{conn: conn} do
    {:ok, view, _html, user} = setup_onboarding(conn)

    html = view |> element("button[phx-click='next_step']") |> render_click()

    assert html =~ "disabled"
    assert html =~ "Customizing it is available on the Pro plan and above."
    refute html =~ ~s(name="username")

    {:ok, profile} = Profiles.get_profile_by_user_id(user.id)
    assert profile.username =~ ~r/\Acalendar-[a-f0-9]{10}\z/
    assert html =~ profile.username
  end

  test "a hand-crafted basic-settings submission cannot override the locked username",
       %{conn: conn} do
    {:ok, view, _html, user} = setup_onboarding(conn)

    view |> element("button[phx-click='next_step']") |> render_click()
    {:ok, original} = Profiles.get_profile_by_user_id(user.id)

    render_change(view, "validate_basic_settings", %{
      "basic_settings" => %{"full_name" => "New Name", "username" => "attempted-change"}
    })

    render_click(view, "update_basic_settings")

    {:ok, updated} = Profiles.get_profile_by_user_id(user.id)
    assert updated.username == original.username
    assert updated.full_name == "New Name"
  end
end

defmodule TymeslotWeb.OnboardingLive.LockedUsernameTest.DenyAccessChecker do
  @moduledoc false

  @spec check_access(any(), atom()) :: :ok | {:error, :insufficient_plan}
  def check_access(_user_id, :custom_username_allowed), do: {:error, :insufficient_plan}
  def check_access(_user_id, _feature), do: :ok
end
