defmodule Tymeslot.Bookings.CreateContactCaptureTest do
  @moduledoc false

  use Tymeslot.DataCase, async: false
  @moduletag :bookings

  alias Tymeslot.Bookings.Create
  alias Tymeslot.Contacts

  import Tymeslot.AvailabilityTestHelpers, only: [open_schedule_for: 1]
  import Tymeslot.BookingCreateTestHelpers

  setup :setup_mock_calendar

  describe "execute/3 contact capture" do
    setup do
      setup_booking_test()
    end

    test "captures a contact when the organizer has collect-contacts enabled" do
      user = insert(:user)
      profile = insert(:profile, user: user, contacts_enabled: true)
      open_schedule_for(profile)
      set_calendar_empty()

      meeting_params = %{
        date: Date.add(Date.utc_today(), 1),
        time: "14:00",
        duration: "60min",
        user_timezone: "America/New_York",
        organizer_user_id: user.id
      }

      form_data = %{
        "name" => "Jane Booker",
        "email" => "jane@example.com",
        "phone" => "555-1234",
        "message" => "Test message"
      }

      assert {:ok, _meeting} = Create.execute(meeting_params, form_data)

      assert [contact] = Contacts.list_contacts(user.id)
      assert contact.name == "Jane Booker"
      assert contact.email == "jane@example.com"
      assert contact.phone == "555-1234"
    end

    test "does not capture a contact when collect-contacts is disabled", %{
      meeting_params: meeting_params,
      form_data: form_data
    } do
      # setup_booking_test's discarded `_profile` belongs to a different
      # user, so `meeting_params.organizer_user_id` has no profile row at
      # all here — contacts_enabled therefore defaults to "off".
      set_calendar_empty()

      assert {:ok, _meeting} = Create.execute(meeting_params, form_data)

      assert Contacts.list_contacts(meeting_params.organizer_user_id) == []
    end
  end
end
