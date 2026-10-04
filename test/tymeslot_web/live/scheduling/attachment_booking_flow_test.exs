defmodule TymeslotWeb.Live.Scheduling.AttachmentBookingFlowTest do
  @moduledoc """
  The booker's side of attachments (TODO #118): the field on the booking form,
  its limits, and the files ending up privately stored on the created meeting —
  or deleted when the booking does not go through. Run against both themes,
  since each renders its own booking component.
  """

  use TymeslotWeb.LiveCase, async: false

  @moduletag :integration
  @moduletag :scheduling
  @moduletag :live

  import Mox
  import Tymeslot.Factory
  import Tymeslot.BookingTestHelpers

  alias Tymeslot.AppSettings
  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Infrastructure.AvailabilityCache
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo
  alias Tymeslot.Security.RateLimiter
  alias Tymeslot.TestMocks

  setup :verify_on_exit!

  setup tags do
    Mox.set_mox_from_context(tags)
    RateLimiter.clear_all()
    AvailabilityCache.clear_all()

    old_recaptcha = Application.get_env(:tymeslot, :recaptcha, [])
    old_uploads = Application.get_env(:tymeslot, :uploads)

    Application.put_env(
      :tymeslot,
      :recaptcha,
      Keyword.put(old_recaptcha, :booking_provider, :off)
    )

    on_exit(fn ->
      Application.put_env(:tymeslot, :recaptcha, old_recaptcha)

      case old_uploads do
        nil -> Application.delete_env(:tymeslot, :uploads)
        value -> Application.put_env(:tymeslot, :uploads, value)
      end
    end)

    TestMocks.setup_all_mocks()

    user = insert(:user)

    profile =
      insert(:profile,
        user: user,
        username: "attachbooker",
        booking_theme: Map.get(tags, :theme, "1"),
        timezone: "America/New_York"
      )

    schedule =
      insert(:availability_schedule,
        profile: profile,
        is_default: true,
        advance_booking_days: 30,
        min_advance_hours: 0,
        buffer_minutes: 0
      )

    Enum.each(1..7, fn day_of_week ->
      insert(:weekly_availability,
        schedule: schedule,
        day_of_week: day_of_week,
        is_available: true,
        start_time: ~T[09:00:00],
        end_time: ~T[17:00:00]
      )
    end)

    insert(:calendar_integration, user: user, is_active: true)

    insert(:meeting_type,
      user: user,
      duration_minutes: 30,
      name: "With files",
      is_active: true,
      allow_attachments: Map.get(tags, :allow_attachments, true)
    )

    %{profile: profile, user: user}
  end

  @booking %{
    "name" => "File Sender",
    "email" => "files@example.com",
    "phone" => "+1 555 900 3000",
    "message" => "Please see the attached brief"
  }

  defp pdf(name \\ "Brief.pdf"),
    do: %{name: name, content: "%PDF-1.4 brief", type: "application/pdf"}

  defp select_files(view, files) do
    input = file_input(view, "#booking-form", :attachments, files)
    Enum.each(files, &render_upload(input, &1.name))
    input
  end

  defp submit(view) do
    view |> form("#booking-form", %{"booking" => @booking}) |> render_submit()
    _drain = :sys.get_state(view.pid)
    render(view)
  end

  defp created_meeting do
    Repo.get_by(MeetingSchema, attendee_email: @booking["email"])
  end

  for theme <- ["1", "2"] do
    describe "theme #{theme}" do
      @describetag theme: theme

      @tag :capture_log
      test "shows the field with the admin's limits", %{conn: conn, profile: profile} do
        view = navigate_to_booking_form(conn, profile, nil)

        assert has_element?(view, "[data-testid='attachment-field']")
        html = render(view)
        assert html =~ "PDF"
        assert html =~ "10 MB"
      end

      @tag :capture_log
      test "stores the files privately on the created meeting", %{
        conn: conn,
        profile: profile
      } do
        view = navigate_to_booking_form(conn, profile, nil)
        select_files(view, [pdf()])

        html = submit(view)
        assert html =~ "Brief.pdf"

        meeting = created_meeting()

        assert [%{"filename" => "Brief.pdf", "content_type" => "application/pdf"} = attachment] =
                 meeting.attendee_attachments

        {:ok, path} = AttendeeAttachments.absolute_path(attachment)
        assert File.read!(path) == "%PDF-1.4 brief"
      end

      @tag :capture_log
      test "refuses a file whose content does not match its type", %{
        conn: conn,
        profile: profile
      } do
        view = navigate_to_booking_form(conn, profile, nil)

        select_files(view, [
          %{name: "virus.pdf", content: "MZ\x90 not a pdf", type: "application/pdf"}
        ])

        html = submit(view)
        assert html =~ "does not match its file type"
        assert created_meeting() == nil
      end
    end
  end

  @tag :capture_log
  test "rejects a type the admin does not allow", %{conn: conn, profile: profile} do
    {:ok, _settings} = AppSettings.update(%{booking_attachment_types: ["docx"]})
    view = navigate_to_booking_form(conn, profile, nil)

    view
    |> file_input("#booking-form", :attachments, [pdf()])
    |> render_upload("Brief.pdf")

    assert render(view) =~ "is not an allowed file type"
  end

  @tag :capture_log
  test "rejects more files than the admin allows", %{conn: conn, profile: profile} do
    {:ok, _settings} = AppSettings.update(%{max_booking_attachments: 1})
    view = navigate_to_booking_form(conn, profile, nil)

    view
    |> file_input("#booking-form", :attachments, [pdf("a.pdf"), pdf("b.pdf")])
    |> render_upload("a.pdf")

    assert render(view) =~ "too many files"
  end

  @tag :capture_log
  @tag allow_attachments: false
  test "the field is absent when the meeting type does not allow it", %{
    conn: conn,
    profile: profile
  } do
    view = navigate_to_booking_form(conn, profile, nil)
    refute has_element?(view, "[data-testid='attachment-field']")
  end

  @tag :capture_log
  test "the field is absent when the admin allows no file type", %{conn: conn, profile: profile} do
    {:ok, _settings} = AppSettings.update(%{booking_attachment_types: []})
    view = navigate_to_booking_form(conn, profile, nil)
    refute has_element?(view, "[data-testid='attachment-field']")
  end

  @tag :capture_log
  test "a booking that fails deletes the files it stored", %{conn: conn, profile: profile} do
    view = navigate_to_booking_form(conn, profile, nil)

    attachment =
      store_pdf_for(:sys.get_state(view.pid).socket.assigns.organizer_user_id)

    send(view.pid, {:step_event, :booking, :attachments, [attachment]})
    # A server-side validation failure (invalid email) keeps the booker on the
    # form without creating a meeting.
    send(
      view.pid,
      {:step_event, :booking, :submit, Map.put(@booking, "email", "not-an-email")}
    )

    _drain = :sys.get_state(view.pid)

    {:ok, path} = AttendeeAttachments.absolute_path(attachment)
    refute File.exists?(path)
    assert :sys.get_state(view.pid).socket.assigns.attendee_attachments == []
  end

  defp store_pdf_for(user_id) do
    tmp = Path.join(System.tmp_dir!(), "attach-flow-#{System.unique_integer([:positive])}")
    File.write!(tmp, "%PDF-1.4")

    {:ok, attachment} =
      AttendeeAttachments.store(
        AttendeeAttachments.new_batch(user_id),
        tmp,
        "a.pdf",
        AttendeeAttachments.allowed_types()
      )

    attachment
  end
end
