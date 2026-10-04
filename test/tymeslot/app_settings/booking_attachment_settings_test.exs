defmodule Tymeslot.AppSettings.BookingAttachmentSettingsTest do
  use Tymeslot.DataCase, async: false

  @moduletag :bookings
  @moduletag :infrastructure
  @moduletag :unit

  alias Tymeslot.AppSettings
  alias Tymeslot.AppSettings.AppSettingsSchema
  alias Tymeslot.Bookings.AttendeeAttachments
  alias TymeslotWeb.Helpers.UploadConstraints

  setup do
    original = Application.get_env(:tymeslot, :uploads)

    on_exit(fn ->
      case original do
        nil -> Application.delete_env(:tymeslot, :uploads)
        value -> Application.put_env(:tymeslot, :uploads, value)
      end
    end)

    :ok
  end

  describe "defaults" do
    test "every supported type but SVG, 10 MB per file, 3 files" do
      assert AppSettings.default_for(:booking_attachment_types) ==
               ~w(csv docx jpeg jpg md ods odt pdf png pptx txt webp xlsx zip)

      assert AppSettings.default_for(:max_booking_attachment_size_mb) == 10
      assert AppSettings.default_for(:max_booking_attachments) == 3
    end
  end

  describe "update/1" do
    test "the supported types are listed alphabetically" do
      types = AppSettingsSchema.booking_attachment_types()
      assert types == Enum.sort(types)
      assert "svg" in types
    end

    test "stores a subset of the supported types and projects it into the upload limits" do
      assert {:ok, _settings} =
               AppSettings.update(%{
                 booking_attachment_types: ["pdf", "docx"],
                 max_booking_attachment_size_mb: 5,
                 max_booking_attachments: 2
               })

      assert UploadConstraints.allowed_extensions(:booking_attachment) == [".pdf", ".docx"]
      assert UploadConstraints.max_file_size(:booking_attachment) == 5_000_000
      assert UploadConstraints.max_entries(:booking_attachment) == 2
    end

    test "rejects a type outside the supported set" do
      assert {:error, changeset} = AppSettings.update(%{booking_attachment_types: ["pdf", "exe"]})
      assert Keyword.has_key?(changeset.errors, :booking_attachment_types)
    end

    test "rejects out-of-range limits" do
      assert {:error, _too_large} = AppSettings.update(%{max_booking_attachment_size_mb: 101})
      assert {:error, _zero} = AppSettings.update(%{max_booking_attachment_size_mb: 0})
      assert {:error, _too_many} = AppSettings.update(%{max_booking_attachments: 11})
    end

    test "an empty type list switches the field off for every meeting type" do
      assert {:ok, _settings} = AppSettings.update(%{booking_attachment_types: []})

      assert AttendeeAttachments.allowed_types() == []
      refute AttendeeAttachments.enabled_for?(%{allow_attachments: true})
    end
  end

  test "a meeting type must opt in" do
    assert AttendeeAttachments.enabled_for?(%{allow_attachments: true})
    refute AttendeeAttachments.enabled_for?(%{allow_attachments: false})
    refute AttendeeAttachments.enabled_for?(nil)
  end
end
