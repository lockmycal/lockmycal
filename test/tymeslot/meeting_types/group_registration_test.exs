defmodule Tymeslot.MeetingTypes.GroupRegistrationTest do
  @moduledoc """
  Who may book a group meeting type: open, or invite-only with a list of
  addresses, and how the meeting-type changeset keeps that list valid.
  """

  use Tymeslot.DataCase, async: true

  @moduletag :meeting_types
  @moduletag :schema

  alias Ecto.Changeset
  alias Tymeslot.MeetingTypes.GroupRegistration
  alias Tymeslot.MeetingTypes.MeetingTypeSchema

  @fixed_location %{kind: "custom", label: "Main hall"}

  defp changeset(attrs) do
    MeetingTypeSchema.changeset(
      %MeetingTypeSchema{},
      Map.merge(
        %{name: "Workshop", duration_minutes: 60, user_id: 1, locations: [@fixed_location]},
        attrs
      )
    )
  end

  describe "parse_list/1" do
    test "splits on lines, commas and semicolons, normalising and de-duplicating" do
      assert GroupRegistration.parse_list(
               " Ada@Example.com\ngrace@example.com, ada@example.com;\n\n"
             ) ==
               ["ada@example.com", "grace@example.com"]
    end

    test "anything that is not text or a list is an empty list" do
      assert GroupRegistration.parse_list(nil) == []
    end
  end

  describe "invited?/2" do
    test "an invite-only group type accepts only listed addresses, case-insensitively" do
      type = %MeetingTypeSchema{
        max_participants: 5,
        registration_mode: "invite_only",
        invited_emails: ["ada@example.com"]
      }

      assert GroupRegistration.invited?(type, " ADA@example.com ")
      refute GroupRegistration.invited?(type, "grace@example.com")
      refute GroupRegistration.invited?(type, nil)
    end

    test "an open or one-to-one type accepts anyone" do
      open = %MeetingTypeSchema{max_participants: 5, registration_mode: "open"}

      solo = %MeetingTypeSchema{
        max_participants: 1,
        registration_mode: "invite_only",
        invited_emails: []
      }

      assert GroupRegistration.invited?(open, "anyone@example.com")
      assert GroupRegistration.invited?(solo, "anyone@example.com")
    end
  end

  describe "the meeting-type changeset" do
    test "stores the list normalised" do
      cs =
        changeset(%{
          max_participants: 5,
          registration_mode: "invite_only",
          invited_emails: [" Ada@Example.com", "ada@example.com"]
        })

      assert cs.valid?
      assert Changeset.get_change(cs, :invited_emails) == ["ada@example.com"]
    end

    test "refuses an unknown mode" do
      refute changeset(%{max_participants: 5, registration_mode: "secret"}).valid?
    end

    test "refuses an invalid address and names it" do
      cs =
        changeset(%{
          max_participants: 5,
          registration_mode: "invite_only",
          invited_emails: ["ada@example.com", "not-an-address"]
        })

      assert {_message, [addresses: "not-an-address"]} = cs.errors[:invited_emails]
    end

    test "an invite-only group type needs at least one address" do
      cs = changeset(%{max_participants: 5, registration_mode: "invite_only", invited_emails: []})

      assert cs.errors[:invited_emails]
    end

    test "a one-to-one type may keep an empty invite-only setting" do
      assert changeset(%{max_participants: 1, registration_mode: "invite_only"}).valid?
    end
  end
end
