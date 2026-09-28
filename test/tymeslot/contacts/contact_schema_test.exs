defmodule Tymeslot.Contacts.ContactSchemaTest do
  use Tymeslot.DataCase, async: true
  @moduletag :contacts
  @moduletag :schema

  alias Tymeslot.Contacts.ContactSchema

  describe "changeset/2" do
    test "valid with required fields" do
      changeset =
        ContactSchema.changeset(%ContactSchema{}, %{
          organizer_user_id: 1,
          name: "Jane Booker",
          email: "jane@example.com"
        })

      assert changeset.valid?
    end

    test "requires name and email" do
      changeset = ContactSchema.changeset(%ContactSchema{}, %{organizer_user_id: 1})

      refute changeset.valid?
      errors = errors_on(changeset)
      assert [_error | _rest] = errors.name
      assert [_error | _rest] = errors.email
    end

    test "rejects an invalid email format" do
      changeset =
        ContactSchema.changeset(%ContactSchema{}, %{
          organizer_user_id: 1,
          name: "Jane Booker",
          email: "not-an-email"
        })

      refute changeset.valid?
      assert [_error | _rest] = errors_on(changeset).email
    end

    test "casts note" do
      changeset =
        ContactSchema.changeset(%ContactSchema{}, %{
          organizer_user_id: 1,
          name: "Jane Booker",
          email: "jane@example.com",
          note: "Prefers afternoons"
        })

      assert get_change(changeset, :note) == "Prefers afternoons"
    end

    test "downcases the email, so the same address in a different casing dedupes on the unique index" do
      changeset =
        ContactSchema.changeset(%ContactSchema{}, %{
          organizer_user_id: 1,
          name: "Jane Booker",
          email: "Jane@Test.COM"
        })

      assert get_change(changeset, :email) == "jane@test.com"
    end
  end

  describe "capture_changeset/2" do
    test "valid with required fields, without a note" do
      changeset =
        ContactSchema.capture_changeset(%ContactSchema{}, %{
          organizer_user_id: 1,
          name: "Jane Booker",
          email: "jane@example.com",
          phone: "555-1234",
          company: "Acme"
        })

      assert changeset.valid?
    end

    test "never casts note, even when supplied" do
      changeset =
        ContactSchema.capture_changeset(%ContactSchema{note: "existing note"}, %{
          organizer_user_id: 1,
          name: "Jane Booker",
          email: "jane@example.com",
          note: "attempted overwrite"
        })

      refute get_change(changeset, :note)
      assert get_field(changeset, :note) == "existing note"
    end

    test "downcases the email" do
      changeset =
        ContactSchema.capture_changeset(%ContactSchema{}, %{
          organizer_user_id: 1,
          name: "Jane Booker",
          email: "Jane@Test.COM"
        })

      assert get_change(changeset, :email) == "jane@test.com"
    end
  end
end
