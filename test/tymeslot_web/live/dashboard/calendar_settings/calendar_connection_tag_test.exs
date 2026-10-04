defmodule TymeslotWeb.Dashboard.CalendarSettings.CalendarConnectionTagTest do
  @moduledoc """
  Type tags registered through `Tymeslot.Dashboard.CalendarConnectionTag` on
  a connected-calendar row.
  """
  # Not async: toggles global app env (registered tags).
  use TymeslotWeb.ConnCase, async: false

  @moduletag :components
  @moduletag :dashboard

  import Phoenix.LiveViewTest
  alias TymeslotWeb.Dashboard.CalendarSettings.CalendarConnectionRow

  defmodule HostedTag do
    @moduledoc false
    @behaviour Tymeslot.Dashboard.CalendarConnectionTag

    @impl Tymeslot.Dashboard.CalendarConnectionTag
    def tag(%{base_url: "https://hosted.example.com/dav"}), do: "Hosted"
    def tag(_integration), do: nil
  end

  setup do
    previous = Application.fetch_env(:tymeslot, :calendar_connection_tags)
    Application.put_env(:tymeslot, :calendar_connection_tags, [HostedTag])

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:tymeslot, :calendar_connection_tags, value)
        :error -> Application.delete_env(:tymeslot, :calendar_connection_tags)
      end
    end)
  end

  test "shows the label a registered module returns for the integration" do
    assert render_row(provider: "radicale", base_url: "https://hosted.example.com/dav") =~
             "Hosted"
  end

  test "shows no tag when no registered module labels the integration" do
    refute render_row(provider: "radicale", base_url: "https://other.example.com/dav") =~
             "Hosted"
  end

  test "Core's read-only tag takes precedence" do
    html = render_row(provider: "ics_url", base_url: "https://hosted.example.com/dav")

    assert html =~ "Read-only"
    refute html =~ "Hosted"
  end

  defp render_row(overrides) do
    integration =
      Enum.into(overrides, %{
        id: 7,
        name: "My calendar",
        is_active: true,
        needs_reauth: false,
        calendar_list: [],
        calendar_paths: [],
        is_primary: false,
        default_booking_calendar_id: nil,
        provider_account_email: nil
      })

    render_component(&CalendarConnectionRow.calendar_connection_row/1,
      integration: integration,
      health_state: nil,
      myself: "target"
    )
  end
end
