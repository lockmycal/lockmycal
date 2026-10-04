defmodule Tymeslot.Bookings.AttendeeAttachmentsTest do
  use Tymeslot.DataCase, async: false

  @moduletag :bookings
  @moduletag :integration

  import Tymeslot.Factory

  alias Ecto.UUID
  alias Tymeslot.Bookings.AttendeeAttachments
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Repo

  @all_types ~w(txt md docx xlsx pdf zip)

  setup do
    tmp =
      Path.join(System.tmp_dir!(), "attendee_attachments_#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf(tmp) end)
    %{tmp: tmp, user: insert(:user)}
  end

  defp temp_file(tmp, content) do
    path = Path.join(tmp, "upload-#{System.unique_integer([:positive])}")
    File.write!(path, content)
    path
  end

  defp store_pdf(tmp, batch, name \\ "Nabídka.pdf") do
    {:ok, attachment} =
      AttendeeAttachments.store(batch, temp_file(tmp, "%PDF-1.4 x"), name, @all_types)

    attachment
  end

  describe "store/4" do
    test "moves the file into the private directory and describes it", %{tmp: tmp, user: user} do
      batch = AttendeeAttachments.new_batch(user.id)
      attachment = store_pdf(tmp, batch, "Nabídka 2026.pdf")

      assert attachment["filename"] == "Nabídka 2026.pdf"
      assert attachment["content_type"] == "application/pdf"
      assert attachment["byte_size"] == byte_size("%PDF-1.4 x")
      assert String.starts_with?(attachment["stored_path"], batch <> "/")

      {:ok, path} = AttendeeAttachments.absolute_path(attachment)
      private_root = Application.fetch_env!(:tymeslot, :private_upload_directory)
      assert String.starts_with?(path, Path.expand(private_root))
      assert File.read!(path) == "%PDF-1.4 x"

      refute String.starts_with?(
               path,
               Path.expand(Application.fetch_env!(:tymeslot, :upload_directory))
             )
    end

    test "keeps only the base name of a path-like client name", %{tmp: tmp, user: user} do
      batch = AttendeeAttachments.new_batch(user.id)
      attachment = store_pdf(tmp, batch, "..\\..\\etc/\"evil\".pdf")

      assert attachment["filename"] == "evil.pdf"
      assert Path.basename(attachment["stored_path"]) == attachment["id"] <> ".pdf"
    end

    test "rejects a type the admin does not allow", %{tmp: tmp, user: user} do
      batch = AttendeeAttachments.new_batch(user.id)

      assert {:error, :invalid_type} =
               AttendeeAttachments.store(batch, temp_file(tmp, "%PDF-"), "a.pdf", ["txt"])
    end

    test "rejects content that does not match the extension", %{tmp: tmp, user: user} do
      batch = AttendeeAttachments.new_batch(user.id)

      assert {:error, :invalid_content} =
               AttendeeAttachments.store(batch, temp_file(tmp, "MZ\x90"), "a.pdf", @all_types)
    end
  end

  describe "absolute_path/1" do
    test "refuses paths that escape the private root" do
      assert {:error, :path_traversal_attempt} =
               AttendeeAttachments.absolute_path("../etc/passwd")

      assert {:error, :path_traversal_attempt} = AttendeeAttachments.absolute_path("/etc/passwd")
    end
  end

  describe "fetch_for_organizer/3" do
    setup %{tmp: tmp, user: user} do
      attachment = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))

      meeting =
        insert(:meeting, organizer_user_id: user.id, attendee_attachments: [attachment])

      %{attachment: attachment, meeting: meeting}
    end

    test "returns the file to the meeting's organiser", ctx do
      assert {:ok, attachment, path} =
               AttendeeAttachments.fetch_for_organizer(
                 ctx.meeting.id,
                 ctx.attachment["id"],
                 ctx.user.id
               )

      assert attachment["id"] == ctx.attachment["id"]
      assert File.regular?(path)
    end

    @tag :cross_tenant
    test "is not_found for anyone else", ctx do
      other = insert(:user)

      assert {:error, :not_found} =
               AttendeeAttachments.fetch_for_organizer(
                 ctx.meeting.id,
                 ctx.attachment["id"],
                 other.id
               )
    end

    test "is not_found for an unknown attachment or meeting", ctx do
      assert {:error, :not_found} =
               AttendeeAttachments.fetch_for_organizer(ctx.meeting.id, "nope", ctx.user.id)

      assert {:error, :not_found} =
               AttendeeAttachments.fetch_for_organizer(
                 UUID.generate(),
                 ctx.attachment["id"],
                 ctx.user.id
               )
    end
  end

  describe "deleting" do
    test "delete_batch/1 removes the batch directory", %{tmp: tmp, user: user} do
      attachment = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))
      {:ok, path} = AttendeeAttachments.absolute_path(attachment)

      assert :ok = AttendeeAttachments.delete_batch([attachment])
      refute File.exists?(Path.dirname(path))
    end

    test "deleting a meeting deletes its files", %{tmp: tmp, user: user} do
      attachment = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))
      {:ok, path} = AttendeeAttachments.absolute_path(attachment)

      meeting =
        insert(:meeting,
          organizer_user_id: user.id,
          organizer_email: user.email,
          attendee_attachments: [attachment]
        )

      assert {:ok, _deleted} = Meetings.delete_meeting_for_user(meeting, user.email)
      refute File.exists?(path)
    end

    test "delete_user_files/1 removes everything of that organiser", %{tmp: tmp, user: user} do
      attachment = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))
      {:ok, path} = AttendeeAttachments.absolute_path(attachment)

      assert :ok = AttendeeAttachments.delete_user_files(user.id)
      refute File.exists?(path)
    end
  end

  describe "prune_orphans/0" do
    test "removes old unreferenced batches and keeps referenced or fresh ones", %{
      tmp: tmp,
      user: user
    } do
      referenced = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))
      insert(:meeting, organizer_user_id: user.id, attendee_attachments: [referenced])

      orphan = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))
      fresh_orphan = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))

      two_days_ago = System.os_time(:second) - 2 * 86_400

      for attachment <- [referenced, orphan] do
        {:ok, path} = AttendeeAttachments.absolute_path(attachment)
        File.touch!(Path.dirname(path), two_days_ago)
      end

      assert AttendeeAttachments.prune_orphans() >= 1

      for {attachment, kept?} <- [{referenced, true}, {orphan, false}, {fresh_orphan, true}] do
        {:ok, path} = AttendeeAttachments.absolute_path(attachment)
        assert File.exists?(path) == kept?
      end
    end
  end

  test "the meeting column round-trips as string-keyed maps", %{tmp: tmp, user: user} do
    attachment = store_pdf(tmp, AttendeeAttachments.new_batch(user.id))
    meeting = insert(:meeting, organizer_user_id: user.id, attendee_attachments: [attachment])

    assert [%{"id" => id, "filename" => "Nabídka.pdf"}] =
             Repo.get!(MeetingSchema, meeting.id).attendee_attachments

    assert id == attachment["id"]
  end
end
