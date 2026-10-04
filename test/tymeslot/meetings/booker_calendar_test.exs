defmodule Tymeslot.Meetings.BookerCalendarTest do
  use Tymeslot.DataCase, async: true
  use Oban.Testing, repo: Tymeslot.Repo

  @moduletag :meetings
  @moduletag :calendar
  @moduletag :unit

  import Mox
  import Tymeslot.Factory

  alias Tymeslot.Bookings.BuildParams
  alias Tymeslot.Bookings.Policy
  alias Tymeslot.Integrations.Calendar
  alias Tymeslot.Meetings.BookerCalendar
  alias Tymeslot.Profiles.ProfileQueries
  alias Tymeslot.Workers.BookerCalendarEventWorker

  setup :verify_on_exit!

  defp booker_with_calendar(attrs \\ []) do
    user = insert(:user)
    insert(:profile, Keyword.merge([user: user], attrs))
    integration = insert(:calendar_integration, user: user, name: "Work calendar")
    {user, integration}
  end

  describe "offer/2" do
    test "names the booker's calendar and their remembered choice" do
      {booker, _integration} = booker_with_calendar()
      organizer = insert(:user)

      assert %{calendar_name: "Work calendar", choice: :ask} =
               BookerCalendar.offer(booker.id, organizer.id)
    end

    test "carries a remembered choice" do
      {booker, _integration} = booker_with_calendar(save_bookings_to_own_calendar: :never)

      assert %{choice: :never} = BookerCalendar.offer(booker.id, insert(:user).id)
    end

    test "names the calendar picked within the booker's default connection" do
      user = insert(:user)
      insert(:profile, user: user)

      integration =
        insert(:calendar_integration,
          user: user,
          name: "SOGo",
          calendar_list: [
            %{"id" => "/cal/personal/", "name" => "Personal", "selected" => true},
            %{"id" => "/cal/work/", "name" => "Work", "selected" => true}
          ]
        )

      {:ok, _integration} =
        Calendar.set_default_integration(
          user.id,
          integration.id,
          "/cal/work/"
        )

      assert %{calendar_name: "SOGo – Work"} = BookerCalendar.offer(user.id, insert(:user).id)
      assert {%{id: id}, %{id: "/cal/work/"}} = BookerCalendar.target(user.id)
      assert id == integration.id
    end

    test "offers nothing to a visitor who is not signed in" do
      assert BookerCalendar.offer(nil, insert(:user).id) == nil
    end

    test "offers nothing to the organiser booking on their own page" do
      {booker, _integration} = booker_with_calendar()

      assert BookerCalendar.offer(booker.id, booker.id) == nil
    end

    test "offers nothing without a calendar that can take the booking" do
      user = insert(:user)
      insert(:profile, user: user)
      insert(:calendar_integration, user: user, needs_reauth: true)

      assert BookerCalendar.offer(user.id, insert(:user).id) == nil
    end
  end

  describe "consent/3" do
    test "no offer means no copy" do
      assert BookerCalendar.consent(nil, true, true) == {false, nil}
    end

    test "a remembered choice applies whatever the form says" do
      assert BookerCalendar.consent(%{choice: :always}, false, true) == {true, nil}
      assert BookerCalendar.consent(%{choice: :never}, true, true) == {false, nil}
    end

    test "asking follows the checkbox and remembers only when asked to" do
      assert BookerCalendar.consent(%{choice: :ask}, true, false) == {true, nil}
      assert BookerCalendar.consent(%{choice: :ask}, false, false) == {false, nil}
      assert BookerCalendar.consent(%{choice: :ask}, true, true) == {true, :always}
      assert BookerCalendar.consent(%{choice: :ask}, false, true) == {false, :never}
    end
  end

  describe "remember/2 and choice/1" do
    test "stores the choice on the profile" do
      user = insert(:user)
      insert(:profile, user: user)

      assert BookerCalendar.choice(user.id) == :ask
      assert :ok = BookerCalendar.remember(user.id, :always)
      assert BookerCalendar.choice(user.id) == :always
    end
  end

  describe "follow/1" do
    test "enqueues a sync for a meeting whose booker asked for a copy" do
      {booker, _integration} = booker_with_calendar()
      meeting = insert(:meeting, booker_user_id: booker.id)

      assert :ok = BookerCalendar.follow(meeting.id)

      assert_enqueued(worker: BookerCalendarEventWorker, args: %{"meeting_id" => meeting.id})
    end

    test "enqueues one sync however many changes arrive before it runs" do
      {booker, _integration} = booker_with_calendar()
      meeting = insert(:meeting, booker_user_id: booker.id)

      BookerCalendar.follow(meeting.id)
      BookerCalendar.follow(meeting.id)

      assert [_one] = all_enqueued(worker: BookerCalendarEventWorker)
    end

    test "every write to the organiser's calendar brings the copy along" do
      {booker, _integration} = booker_with_calendar()
      meeting = insert(:meeting, booker_user_id: booker.id, status: "cancelled")

      assert :ok =
               perform_job(Tymeslot.Workers.CalendarEventWorker, %{
                 "action" => "delete",
                 "meeting_id" => meeting.id
               })

      assert_enqueued(worker: BookerCalendarEventWorker, args: %{"meeting_id" => meeting.id})
    end

    test "enqueues nothing for an ordinary booking" do
      meeting = insert(:meeting)

      assert :ok = BookerCalendar.follow(meeting.id)

      refute_enqueued(worker: BookerCalendarEventWorker)
    end
  end

  describe "Policy.build_meeting_attributes/1" do
    setup do
      organizer = insert(:user)
      insert(:profile, user: organizer)

      stub(Tymeslot.CalendarMock, :get_booking_integration_info, fn _context ->
        {:error, :no_integration}
      end)

      params = %{
        meeting_uid: "meeting-uid",
        start_datetime: DateTime.add(DateTime.utc_now(), 3600, :second),
        end_datetime: DateTime.add(DateTime.utc_now(), 5400, :second),
        duration_minutes: 30,
        form_data: %{"name" => "Attendee", "email" => "attendee@example.com"},
        organizer_user_id: organizer.id,
        user_timezone: "UTC"
      }

      %{organizer: organizer, params: params}
    end

    test "records the booker who asked for a copy", %{params: params} do
      booker = insert(:user)

      attrs =
        Policy.build_meeting_attributes(
          BuildParams.new(Map.put(params, :booker_user_id, booker.id))
        )

      assert attrs.booker_user_id == booker.id
    end

    test "never records the organiser as their own booker", %{
      organizer: organizer,
      params: params
    } do
      attrs =
        Policy.build_meeting_attributes(
          BuildParams.new(Map.put(params, :booker_user_id, organizer.id))
        )

      assert attrs.booker_user_id == nil
    end

    test "keeps the host's email and phone from the booker unless the meeting type shares them",
         %{organizer: organizer, params: params} do
      {:ok, profile} = ProfileQueries.get_by_user_id(organizer.id)
      {:ok, _profile} = ProfileQueries.update_profile(profile, %{phone: "+420777888999"})
      private = insert(:meeting_type, user: organizer)

      attrs =
        Policy.build_meeting_attributes(
          BuildParams.new(Map.put(params, :meeting_type_id, private.id))
        )

      refute attrs.share_organizer_email
      assert attrs.organizer_phone == nil

      shared =
        insert(:meeting_type,
          user: organizer,
          show_email_to_bookers: true,
          show_phone_to_bookers: true
        )

      attrs =
        Policy.build_meeting_attributes(
          BuildParams.new(Map.put(params, :meeting_type_id, shared.id))
        )

      assert attrs.share_organizer_email
      assert attrs.organizer_phone == "+420777888999"
    end
  end
end
