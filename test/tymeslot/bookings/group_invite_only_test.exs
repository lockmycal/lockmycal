defmodule Tymeslot.Bookings.GroupInviteOnlyTest do
  @moduledoc """
  An invite-only group meeting type takes seats only from the addresses on
  its list, each for the booker alone; an open one takes anyone.
  """

  use Tymeslot.DataCase, async: false
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :bookings
  @moduletag :integration

  import Mox
  import Tymeslot.AvailabilityTestHelpers
  import Tymeslot.Factory

  alias Ecto.Changeset
  alias Tymeslot.Bookings.Create
  alias Tymeslot.Meetings.GuestSchema
  alias Tymeslot.Meetings.ParticipantQueries
  alias Tymeslot.Meetings.ParticipantSchema
  alias Tymeslot.Repo

  setup :verify_on_exit!

  setup do
    stub(Tymeslot.CalendarMock, :get_booking_integration_info, fn _context ->
      {:error, :no_integration}
    end)

    user = insert(:user)
    profile = insert(:profile, user: user)
    _schedule = open_schedule_for(profile)

    meeting_type =
      insert(:meeting_type,
        user: user,
        max_participants: 3,
        allow_guests: true,
        registration_mode: "invite_only",
        invited_emails: ["ada@example.com", "grace@example.com"]
      )

    meeting_params = %{
      date: Date.add(Date.utc_today(), 5),
      time: "10:00",
      duration: "30min",
      user_timezone: "Etc/UTC",
      organizer_user_id: user.id,
      meeting_type_id: meeting_type.id
    }

    %{meeting_type: meeting_type, meeting_params: meeting_params}
  end

  defp execute(ctx, email, extra_params \\ %{}) do
    Create.execute(
      Map.merge(ctx.meeting_params, extra_params),
      %{"name" => "Booker", "email" => email, "message" => ""},
      skip_calendar_check: true
    )
  end

  test "an invited address books a seat, compared case-insensitively", ctx do
    assert {:ok, meeting} = execute(ctx, "  Ada@Example.com ")

    assert [participant] = ParticipantQueries.list_live_for_meeting(meeting.id)
    assert String.downcase(String.trim(participant.email)) == "ada@example.com"
  end

  test "an address not on the list is refused before any seat is taken", ctx do
    assert {:error, :not_invited} = execute(ctx, "stranger@example.com")
    assert Repo.all(ParticipantSchema) == []
  end

  test "guests are not taken on an invite-only type", ctx do
    assert {:ok, meeting} =
             execute(ctx, "ada@example.com", %{guest_emails: ["friend@example.com"]})

    assert Repo.all(from(g in GuestSchema, where: g.meeting_id == ^meeting.id)) == []
  end

  test "an open group type takes anyone", ctx do
    ctx.meeting_type
    |> Changeset.change(registration_mode: "open")
    |> Repo.update!()

    assert {:ok, _meeting} = execute(ctx, "stranger@example.com")
  end

  test "the list is ignored once the type is one-to-one", ctx do
    ctx.meeting_type
    |> Changeset.change(max_participants: 1)
    |> Repo.update!()

    assert {:ok, _meeting} = execute(ctx, "stranger@example.com")
  end
end
