defmodule TymeslotWeb.Dashboard.CalendarSettingsExtraSectionsTest do
  @moduledoc """
  Sections registered through `Tymeslot.Dashboard.CalendarSettingsSection`
  on the dashboard's Calendars page.
  """
  # Not async: toggles global app env (registered sections).
  use TymeslotWeb.ConnCase, async: false

  @moduletag :live
  @moduletag :dashboard

  import Phoenix.LiveViewTest
  import Tymeslot.AuthTestHelpers
  import Tymeslot.Factory

  defmodule TestSection do
    @moduledoc false
    @behaviour Tymeslot.Dashboard.CalendarSettingsSection

    use Phoenix.Component

    @impl Tymeslot.Dashboard.CalendarSettingsSection
    def id, do: :test_hosted

    @impl Tymeslot.Dashboard.CalendarSettingsSection
    def render(user, integrations) do
      assigns = %{email: user.email, count: length(integrations)}

      ~H"""
      <div class="card-glass">Hosted calendar for {@email} ({@count} connected)</div>
      """
    end
  end

  defmodule HiddenSection do
    @moduledoc false
    @behaviour Tymeslot.Dashboard.CalendarSettingsSection

    @impl Tymeslot.Dashboard.CalendarSettingsSection
    def id, do: :hidden

    @impl Tymeslot.Dashboard.CalendarSettingsSection
    def render(_user, _integrations), do: nil
  end

  setup %{conn: conn} do
    user = insert(:user, onboarding_completed_at: DateTime.utc_now(:second))
    _profile = insert(:profile, user: user, timezone: "Etc/UTC")

    previous = Application.fetch_env(:tymeslot, :calendar_settings_extra_sections)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:tymeslot, :calendar_settings_extra_sections, value)
        :error -> Application.delete_env(:tymeslot, :calendar_settings_extra_sections)
      end
    end)

    {:ok, conn: log_in_user(conn, user), user: user}
  end

  test "renders nothing extra when no section is registered", %{conn: conn} do
    Application.delete_env(:tymeslot, :calendar_settings_extra_sections)

    {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")

    refute has_element?(view, "[id^='calendar-settings-section-']")
  end

  test "renders registered sections, skipping ones that return nil",
       %{conn: conn, user: user} do
    Application.put_env(:tymeslot, :calendar_settings_extra_sections, [
      TestSection,
      HiddenSection
    ])

    {:ok, view, _html} = live(conn, ~p"/dashboard/calendar-integration")

    assert view |> element("#calendar-settings-section-test_hosted") |> render() =~
             "Hosted calendar for #{user.email} (0 connected)"

    refute view |> element("#calendar-settings-section-hidden") |> render() =~ "card-glass"
  end
end
