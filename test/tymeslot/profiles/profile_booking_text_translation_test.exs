defmodule Tymeslot.Profiles.ProfileBookingTextTranslationTest do
  use Tymeslot.DataCase, async: true

  @moduletag :profiles
  @moduletag :schema

  alias Ecto.Changeset
  alias Tymeslot.Profiles.ProfileBookingTextTranslation

  describe "changeset/2" do
    test "requires a locale" do
      cs =
        ProfileBookingTextTranslation.changeset(%ProfileBookingTextTranslation{}, %{
          "booking_heading" => "Hallo"
        })

      refute cs.valid?
      assert "can't be blank" in errors_on(cs).locale
    end

    test "a partial row (heading only) is valid — unlike the base changeset's all-or-nothing rule" do
      cs =
        ProfileBookingTextTranslation.changeset(%ProfileBookingTextTranslation{}, %{
          "locale" => "de",
          "booking_heading" => "Lass uns reden"
        })

      assert cs.valid?
    end

    test "accepts all three fields set" do
      attrs = %{
        "locale" => "de",
        "booking_heading" => "Lass uns reden",
        "booking_greeting" => "Hallo, ich bin Sam.",
        "booking_instruction" => "Wähle einen Termin unten."
      }

      cs = ProfileBookingTextTranslation.changeset(%ProfileBookingTextTranslation{}, attrs)
      assert cs.valid?
    end

    test "rejects an unsupported locale code" do
      cs =
        ProfileBookingTextTranslation.changeset(%ProfileBookingTextTranslation{}, %{
          "locale" => "xx"
        })

      refute cs.valid?
      assert "is invalid" in errors_on(cs).locale
    end

    test "auto-fills id when absent" do
      cs =
        ProfileBookingTextTranslation.changeset(%ProfileBookingTextTranslation{}, %{
          "locale" => "de"
        })

      assert cs |> Changeset.get_field(:id) |> byte_size() > 0
    end

    test "a blank field is normalised to nil, not an empty string" do
      cs =
        ProfileBookingTextTranslation.changeset(
          %ProfileBookingTextTranslation{booking_heading: "Old"},
          %{"locale" => "de", "booking_heading" => ""}
        )

      assert Changeset.get_field(cs, :booking_heading) == nil
    end

    test "rejects a heading over the shared heading length cap" do
      cs =
        ProfileBookingTextTranslation.changeset(%ProfileBookingTextTranslation{}, %{
          "locale" => "de",
          "booking_heading" => String.duplicate("a", 61)
        })

      refute cs.valid?
      assert "should be at most 60 character(s)" in errors_on(cs).booking_heading
    end

    test "rejects a greeting over the shared welcome-line length cap" do
      cs =
        ProfileBookingTextTranslation.changeset(%ProfileBookingTextTranslation{}, %{
          "locale" => "de",
          "booking_greeting" => String.duplicate("a", 81)
        })

      refute cs.valid?
      assert "should be at most 80 character(s)" in errors_on(cs).booking_greeting
    end
  end
end
