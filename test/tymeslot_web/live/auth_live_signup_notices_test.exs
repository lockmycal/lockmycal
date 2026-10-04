defmodule TymeslotWeb.AuthLiveSignupNoticesTest do
  @moduledoc """
  Notices registered through `Tymeslot.Auth.SignupNotice` on the signup form.
  """
  # Not async: toggles global app env (registered notices).
  use TymeslotWeb.LiveCase, async: false

  @moduletag :auth
  @moduletag :live

  defmodule TestNotice do
    @moduledoc false
    @behaviour Tymeslot.Auth.SignupNotice

    use Phoenix.Component

    @impl Tymeslot.Auth.SignupNotice
    def id, do: :test_plan

    @impl Tymeslot.Auth.SignupNotice
    def render do
      assigns = %{}

      ~H"""
      <p>Plan notice text</p>
      """
    end
  end

  defmodule HiddenNotice do
    @moduledoc false
    @behaviour Tymeslot.Auth.SignupNotice

    @impl Tymeslot.Auth.SignupNotice
    def id, do: :hidden

    @impl Tymeslot.Auth.SignupNotice
    def render, do: nil
  end

  setup do
    previous = Application.fetch_env(:tymeslot, :signup_extra_notices)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:tymeslot, :signup_extra_notices, value)
        :error -> Application.delete_env(:tymeslot, :signup_extra_notices)
      end
    end)

    :ok
  end

  test "renders nothing extra when no notice is registered", %{conn: conn} do
    Application.delete_env(:tymeslot, :signup_extra_notices)

    {:ok, view, _html} = live(conn, "/auth/signup")

    refute has_element?(view, "[id^='signup-notice-']")
  end

  test "renders registered notices, skipping ones that return nil", %{conn: conn} do
    Application.put_env(:tymeslot, :signup_extra_notices, [TestNotice, HiddenNotice])

    {:ok, view, _html} = live(conn, "/auth/signup")

    assert view |> element("#signup-notice-test_plan") |> render() =~ "Plan notice text"
    refute view |> element("#signup-notice-hidden") |> render() =~ "<p>"
  end
end
