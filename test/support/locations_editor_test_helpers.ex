defmodule Tymeslot.LocationsEditorTestHelpers do
  @moduledoc """
  Shared helpers for the meeting type form's locations editor tests.
  """
  use Phoenix.VerifiedRoutes, endpoint: TymeslotWeb.Endpoint, router: TymeslotWeb.Router

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Tymeslot.Factory

  @endpoint TymeslotWeb.Endpoint

  alias Tymeslot.MeetingTypes
  alias Tymeslot.MeetingTypes.LocationOption
  alias Tymeslot.MeetingTypes.MeetingTypeSchema

  @doc "Opens the meeting type form's Location tab for a new meeting type with `locations`."
  @spec open_editor(map(), [LocationOption.t()]) ::
          {Phoenix.LiveViewTest.View.t(), MeetingTypeSchema.t()}
  def open_editor(%{conn: conn, user: user}, locations) do
    meeting_type =
      insert(:meeting_type,
        user: user,
        name: "Consultation",
        duration_minutes: 30,
        locations: locations
      )

    {:ok, view, _html} = live(conn, ~p"/dashboard/meeting-settings")

    view
    |> element("[phx-click='edit_type'][phx-value-id='#{meeting_type.id}']")
    |> render_click()

    view |> element("[phx-click='switch_tab'][phx-value-tab='location']") |> render_click()

    {view, meeting_type}
  end

  # The editor and the list both mutate via `send_update`, which is delivered
  # as a message *after* the event round-trip returns. Draining the LiveView's
  # mailbox is what makes the auto-save it triggers observable here.
  @spec reload(Phoenix.LiveViewTest.View.t(), MeetingTypeSchema.t(), map()) ::
          MeetingTypeSchema.t() | nil
  def reload(view, meeting_type, user) do
    _drain = :sys.get_state(view.pid)
    MeetingTypes.get_meeting_type(meeting_type.id, user.id)
  end

  @spec change_duration(Phoenix.LiveViewTest.View.t(), integer()) :: term()
  def change_duration(view, minutes) do
    view |> element("[phx-click='switch_tab'][phx-value-tab='details']") |> render_click()

    view
    |> element(~s|input[name="meeting_type[duration]"]|)
    |> render_change(%{"meeting_type" => %{"duration" => minutes}})
  end

  @spec office() :: LocationOption.t()
  def office do
    %LocationOption{
      id: "loc-office",
      kind: "in_person",
      label: "Our office",
      position: 0
    }
  end
end
