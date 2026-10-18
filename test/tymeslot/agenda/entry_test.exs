defmodule Tymeslot.Agenda.EntryTest do
  @moduledoc """
  The agenda's entries on their own: a calendar grid event turned into an
  agenda entry (`Agenda.entry_for_grid_event/2`), and whether an entry covers
  a day (`Entry.covers?/3`).
  """

  use ExUnit.Case, async: true
  @moduletag :calendar

  alias Tymeslot.Agenda
  alias Tymeslot.Agenda.Entry

  describe "entry_for_grid_event/2" do
    test "describes a booking projection as a Tymeslot entry with its attendee" do
      booking = %Tymeslot.CalendarGrid.BookingEvent{
        id: "booking-m1",
        meeting_id: "m1",
        summary: "Discovery call",
        start_at: ~U[2026-07-02 23:30:00Z],
        end_at: ~U[2026-07-03 00:00:00Z],
        attendee_name: "Ada Lovelace",
        attendee_email: "ada@example.com",
        join_url: "https://zoom.us/j/1",
        location: " "
      }

      entry = Agenda.entry_for_grid_event(booking, "Europe/Berlin")

      assert %Entry{
               id: "meeting-m1",
               source: :tymeslot,
               title: "Discovery call",
               who: "Ada Lovelace",
               who_email: "ada@example.com",
               join_url: "https://zoom.us/j/1",
               location: nil,
               source_id: "m1",
               target: {:meeting, "m1"},
               all_day?: false
             } = entry

      # The day is the organiser's local one: 23:30 UTC is already the 3rd in Berlin.
      assert entry.day == ~D[2026-07-03]
    end

    test "describes a provider event, leaving a missing title for the caller to label" do
      event = %{
        id: 42,
        uid: "uid-42",
        calendar_integration_id: 7,
        summary: nil,
        all_day: false,
        start_at: ~U[2026-07-02 09:00:00Z],
        end_at: ~U[2026-07-02 10:00:00Z],
        location: "Room 3B",
        video_link: "https://meet.example.com/x",
        organiser: %{"displayName" => "Sam Rivera"},
        colour: "blueberry"
      }

      assert %Entry{
               id: "event-42",
               source: :external,
               title: nil,
               day: ~D[2026-07-02],
               location: "Room 3B",
               join_url: "https://meet.example.com/x",
               who: "Sam Rivera",
               colour: "blueberry",
               source_id: 42,
               target: {:external, 7, "uid-42"}
             } = Agenda.entry_for_grid_event(event, "Etc/UTC")
    end

    test "holds an all-day event by its dates, ending at the midnight after the last" do
      event = %{
        id: 43,
        all_day: true,
        start_date: ~D[2026-07-02],
        end_date: ~D[2026-07-04],
        start_at: nil,
        end_at: nil,
        summary: "Offsite"
      }

      entry = Agenda.entry_for_grid_event(event, "Etc/UTC")

      assert entry.all_day?
      assert entry.day == ~D[2026-07-02]
      assert entry.start_at == ~U[2026-07-02 00:00:00Z]
      assert entry.end_at == ~U[2026-07-04 00:00:00Z]
    end
  end

  describe "Entry.covers?/3" do
    test "a same-day timed entry covers only its day" do
      entry = timed_entry(~D[2026-07-02], ~U[2026-07-02 11:00:00Z])

      assert Entry.covers?(entry, ~D[2026-07-02], "Etc/UTC")
      refute Entry.covers?(entry, ~D[2026-07-03], "Etc/UTC")
      refute Entry.covers?(entry, ~D[2026-07-01], "Etc/UTC")
    end

    test "an overnight timed entry covers the day it started and the next" do
      entry = timed_entry(~D[2026-07-02], ~U[2026-07-03 01:00:00Z])

      assert Entry.covers?(entry, ~D[2026-07-02], "Etc/UTC")
      assert Entry.covers?(entry, ~D[2026-07-03], "Etc/UTC")
      refute Entry.covers?(entry, ~D[2026-07-04], "Etc/UTC")
    end

    test "a multi-day all-day entry covers each day in [start, end), end exclusive" do
      # start_date 2 Jul, end_date 5 Jul → end_at is local midnight of 5 Jul.
      entry = all_day_entry(~D[2026-07-02], ~U[2026-07-05 00:00:00Z])

      assert Entry.covers?(entry, ~D[2026-07-02], "Etc/UTC")
      assert Entry.covers?(entry, ~D[2026-07-04], "Etc/UTC")
      refute Entry.covers?(entry, ~D[2026-07-05], "Etc/UTC")
      refute Entry.covers?(entry, ~D[2026-07-01], "Etc/UTC")
    end
  end

  defp timed_entry(day, end_at) do
    %Entry{
      id: "t",
      source: :external,
      title: "t",
      day: day,
      start_at: DateTime.new!(day, ~T[10:00:00], "Etc/UTC"),
      end_at: end_at,
      all_day?: false
    }
  end

  defp all_day_entry(start_date, end_at) do
    %Entry{
      id: "a",
      source: :external,
      title: "a",
      day: start_date,
      start_at: DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC"),
      end_at: end_at,
      all_day?: true
    }
  end
end
