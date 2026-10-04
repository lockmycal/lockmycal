defmodule Tymeslot.Meetings.DisplayTitleTest do
  use ExUnit.Case, async: true

  @moduletag :meetings
  @moduletag :unit

  alias Tymeslot.Meetings.DisplayTitle

  @meeting %{title: "Consultation with Jane", attendee_message: "Kitchen remodel quote"}

  describe "title/2" do
    test "uses the meeting information under \"meeting_info\"" do
      assert DisplayTitle.title(@meeting, "meeting_info") == "Kitchen remodel quote"
    end

    test "reads nil or an unknown source as the default, meeting information" do
      assert DisplayTitle.title(@meeting, nil) == "Kitchen remodel quote"
      assert DisplayTitle.title(@meeting, "bogus") == "Kitchen remodel quote"
    end

    test "takes only the first non-blank line of multi-line meeting information" do
      meeting = %{@meeting | attendee_message: "\r\n   \r\n  First line  \r\nSecond line"}
      assert DisplayTitle.title(meeting, "meeting_info") == "First line"
    end

    test "falls back to the booking's own title without meeting information" do
      for message <- [nil, "", "  \n  "] do
        meeting = %{@meeting | attendee_message: message}
        assert DisplayTitle.title(meeting, "meeting_info") == "Consultation with Jane"
      end
    end

    test "uses the booking's own title under \"meeting_type\"" do
      assert DisplayTitle.title(@meeting, "meeting_type") == "Consultation with Jane"
    end

    test "falls back to a generic title when the booking has none" do
      assert DisplayTitle.title(%{title: " ", attendee_message: nil}, "meeting_type") == "Meeting"
    end
  end

  test "valid?/1 accepts exactly the offered sources" do
    assert Enum.all?(DisplayTitle.sources(), &DisplayTitle.valid?/1)
    refute DisplayTitle.valid?("bogus")
    refute DisplayTitle.valid?(nil)
  end
end
