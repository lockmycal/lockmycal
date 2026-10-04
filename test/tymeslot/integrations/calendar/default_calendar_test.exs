defmodule Tymeslot.Integrations.Calendar.DefaultCalendarTest do
  @moduledoc """
  The default calendar is a calendar, not a whole connection: on a connection
  with several, the one picked is remembered, and only one that can take a
  booking can be picked.
  """
  use Tymeslot.DataCase, async: true

  @moduletag :calendar

  import Tymeslot.Factory

  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Profiles.ProfileQueries

  setup do
    user = insert(:user)
    insert(:profile, user: user)

    integration =
      insert(:calendar_integration,
        user: user,
        calendar_list: [
          %{"id" => "/cal/personal/", "name" => "Personal", "selected" => true},
          %{"id" => "/cal/work/", "name" => "Work", "selected" => true},
          %{"id" => "/cal/shared/", "name" => "Shared", "selected" => true, "read_only" => true},
          %{"id" => "/cal/off/", "name" => "Not synced", "selected" => false}
        ]
      )

    %{user: user, integration: integration}
  end

  test "remembers the calendar picked within the default connection", ctx do
    assert {:ok, _integration} =
             Calendar.set_default_integration(ctx.user.id, ctx.integration.id, "/cal/work/")

    assert Calendar.default_calendar(ctx.user.id) == {ctx.integration.id, "/cal/work/"}

    assert [%{is_primary: true, default_calendar_id: "/cal/work/"}] =
             Calendar.list_integrations(ctx.user.id)
  end

  test "refuses a calendar that cannot take a booking", ctx do
    for calendar_id <- ["/cal/shared/", "/cal/off/", "/cal/elsewhere/"] do
      assert {:error, :not_bookable} =
               Calendar.set_default_integration(ctx.user.id, ctx.integration.id, calendar_id)
    end

    assert Calendar.default_calendar(ctx.user.id) == {nil, nil}
  end

  test "another connection becoming the default drops the pick", ctx do
    {:ok, _integration} =
      Calendar.set_default_integration(ctx.user.id, ctx.integration.id, "/cal/work/")

    # Promoting the same connection again, as reactivating it does, keeps it.
    {:ok, _profile} =
      ProfileQueries.set_primary_calendar_integration(ctx.user.id, ctx.integration.id)

    assert Calendar.default_calendar(ctx.user.id) == {ctx.integration.id, "/cal/work/"}

    other = insert(:calendar_integration, user: ctx.user)
    {:ok, _profile} = ProfileQueries.set_primary_calendar_integration(ctx.user.id, other.id)
    assert Calendar.default_calendar(ctx.user.id) == {other.id, nil}
  end
end
