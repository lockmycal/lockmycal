defmodule Tymeslot.Integrations.Calendar.IcsGeneratorBrandingTest do
  @moduledoc """
  The "Scheduled with <app name>" footer in an `.ics` description
  (`Tymeslot.Profiles.IcsBranding`): there for every organiser while the
  instance has a footer link, left out only by an organiser who switched it
  off and whose plan allows custom branding.
  """

  # Swaps the global `:ics_branding_url` and feature checker settings.
  use Tymeslot.DataCase, async: false
  @moduletag :integrations
  @moduletag :profiles

  import Tymeslot.ConfigTestHelpers

  alias Tymeslot.Emails.Templates.CalendarInvitation
  alias Tymeslot.Infrastructure.Config
  alias Tymeslot.Integrations.Calendar.IcsGenerator
  alias Tymeslot.Meetings
  alias Tymeslot.Profiles
  alias Tymeslot.Workers.EmailWorkerHandlers.CalendarEventDetails

  @url "https://lockmycal.example.com"
  @footer "Scheduled with #{Config.app_name()}: #{@url}"

  defmodule DenyBrandingChecker do
    @behaviour Tymeslot.Features.CheckerBehaviour
    @impl Tymeslot.Features.CheckerBehaviour
    def check_access(_user_id, :custom_branding_allowed), do: {:error, :insufficient_plan}
    def check_access(_user_id, _feature), do: :ok
  end

  setup do
    setup_config(:tymeslot,
      ics_branding_url: @url,
      feature_access_checker: Tymeslot.Features.DefaultAccessChecker
    )

    user = insert(:user)
    insert(:profile, user: user)
    %{user: user}
  end

  defp ics(overrides) do
    %{
      title: "Intro call",
      description: "Agenda",
      start_time: ~U[2026-11-02 14:00:00Z],
      end_time: ~U[2026-11-02 14:30:00Z],
      uid: "branding-test",
      organizer_email: "host@example.com",
      organizer_name: "Host"
    }
    |> Map.merge(overrides)
    |> IcsGenerator.generate_ics()
    |> unfold()
  end

  defp unfold(ics), do: String.replace(ics, "\r\n ", "")

  defp switch_off(user) do
    user.id
    |> Profiles.get_profile()
    |> Profiles.update_profile_field(:ics_branding_enabled, false)
  end

  test "an organiser's event ends its description with the footer by default", %{user: user} do
    assert ics(%{organizer_user_id: user.id}) =~ "Agenda\\n\\n#{@footer}\nLOCATION"
  end

  test "an organiser allowed custom branding who switched it off gets none", %{user: user} do
    {:ok, _profile} = switch_off(user)

    refute ics(%{organizer_user_id: user.id}) =~ @footer
  end

  test "switching it off counts only while the plan allows custom branding", %{user: user} do
    {:ok, _profile} = switch_off(user)
    setup_config(:tymeslot, feature_access_checker: DenyBrandingChecker)

    assert ics(%{organizer_user_id: user.id}) =~ @footer
  end

  test "an event with no known organiser carries the footer" do
    assert ics(%{}) =~ @footer
  end

  test "an instance with no footer link carries none", %{user: user} do
    setup_config(:tymeslot, ics_branding_url: nil)

    refute ics(%{organizer_user_id: user.id}) =~ "Scheduled with"
  end

  test "the footer follows the attendee's language", %{user: user} do
    ics =
      IcsGenerator.generate_ics(
        %{
          title: "Intro call",
          start_time: ~U[2026-11-02 14:00:00Z],
          end_time: ~U[2026-11-02 14:30:00Z],
          organizer_email: "host@example.com",
          organizer_name: "Host",
          organizer_user_id: user.id
        },
        "de"
      )

    assert unfold(ics) =~ "Geplant mit #{Config.app_name()}: #{@url}"
  end

  test "a dashboard event's invitation email carries its organiser's footer", %{user: user} do
    {:ok, details} =
      CalendarEventDetails.invitation_details(
        %{id: user.id, name: "Host", email: "host@example.com"},
        %{
          "event_title" => "Planning",
          "event_uid" => "invite-branding",
          "event_start_at" => "2026-11-02T14:00:00Z",
          "event_end_at" => "2026-11-02T15:00:00Z"
        }
      )

    email = CalendarInvitation.render("guest@example.com", details)

    [attachment] = Enum.filter(email.attachments, &(&1.content_type == "text/calendar"))
    assert unfold(attachment.data) =~ @footer
  end

  describe "a stored booking" do
    setup %{user: user} do
      start_time = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      meeting =
        insert(:meeting,
          organizer_user: user,
          organizer_user_id: user.id,
          status: "confirmed",
          start_time: start_time,
          end_time: DateTime.add(start_time, 3600)
        )

      %{meeting: meeting}
    end

    test "the attendee's calendar download carries the organiser's footer", %{
      meeting: meeting,
      user: user
    } do
      assert {:ok, ics} = Meetings.calendar_export(meeting.uid, user.id)
      assert unfold(ics) =~ @footer
    end

    test "a download of an organiser who switched it off carries none", %{
      meeting: meeting,
      user: user
    } do
      {:ok, _profile} = switch_off(user)

      assert {:ok, ics} = Meetings.calendar_export(meeting.uid, user.id)
      refute unfold(ics) =~ @footer
    end
  end
end
