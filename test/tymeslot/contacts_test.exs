defmodule Tymeslot.ContactsTest do
  use Tymeslot.DataCase, async: false
  @moduletag :contacts

  import Tymeslot.ConfigTestHelpers
  import Tymeslot.Factory

  alias Tymeslot.Contacts

  setup do
    # Contacts CRUD/capture gating goes through Features.check_access/2, which
    # is config-swappable for SaaS subscription checking. Pin to the Core
    # default so this test is not affected by whichever checker another test
    # left configured.
    setup_config(:tymeslot, feature_access_checker: Tymeslot.Features.DefaultAccessChecker)
    :ok
  end

  describe "list_contacts_page/4" do
    test "pages the organizer's contacts by name, filtered by the search" do
      user = insert(:user)
      insert(:contact, organizer_user: insert(:user), name: "Someone else's")

      for n <- 1..25 do
        insert(:contact,
          organizer_user: user,
          name: "Contact #{String.pad_leading("#{n}", 2, "0")}"
        )
      end

      first = Contacts.list_contacts_page(user.id, "", 1, 20)
      assert %{total: 25, total_pages: 2, page: 1} = first
      assert hd(first.entries).name == "Contact 01"

      assert %{entries: second} = Contacts.list_contacts_page(user.id, "", 2, 20)
      assert Enum.map(second, & &1.name) == Enum.map(21..25, &"Contact #{&1}")

      assert %{total: 1, entries: [%{name: "Contact 07"}]} =
               Contacts.list_contacts_page(user.id, "07", 1, 20)
    end
  end

  describe "create_contact/2" do
    test "creates a contact for the user" do
      user = insert(:user)

      assert {:ok, contact} =
               Contacts.create_contact(user.id, %{name: "Jane Booker", email: "jane@example.com"})

      assert contact.organizer_user_id == user.id
      assert contact.name == "Jane Booker"
    end

    test "returns an error changeset when required fields are missing" do
      user = insert(:user)

      assert {:error, changeset} = Contacts.create_contact(user.id, %{})
      errors = errors_on(changeset)
      assert [_error | _rest] = errors.name
      assert [_error | _rest] = errors.email
    end
  end

  describe "update_contact/2" do
    test "updates the contact's fields" do
      contact = insert(:contact, name: "Old Name")

      assert {:ok, updated} = Contacts.update_contact(contact, %{name: "New Name"})
      assert updated.name == "New Name"
    end
  end

  describe "delete_contact/1" do
    test "deletes the contact" do
      contact = insert(:contact)

      assert {:ok, _deleted} = Contacts.delete_contact(contact)
      assert {:error, :not_found} = Contacts.get_contact(contact.id, contact.organizer_user_id)
    end
  end

  describe "capture_from_booking/2" do
    test "creates a contact when the organizer has collection enabled" do
      user = insert(:user)
      insert(:profile, user: user, contacts_enabled: true)

      assert :ok =
               Contacts.capture_from_booking(user.id, %{
                 name: "Jane Booker",
                 email: "jane@example.com",
                 phone: "555-1234",
                 company: "Acme"
               })

      assert [contact] = Contacts.list_contacts(user.id)
      assert contact.email == "jane@example.com"
    end

    test "is a no-op when the organizer has collection disabled" do
      user = insert(:user)
      insert(:profile, user: user, contacts_enabled: false)

      assert :ok =
               Contacts.capture_from_booking(user.id, %{
                 name: "Jane Booker",
                 email: "jane@example.com"
               })

      assert Contacts.list_contacts(user.id) == []
    end

    test "is a no-op when the organizer has no profile at all" do
      user = insert(:user)

      assert :ok =
               Contacts.capture_from_booking(user.id, %{
                 name: "Jane Booker",
                 email: "jane@example.com"
               })

      assert Contacts.list_contacts(user.id) == []
    end

    test "updates the existing contact without overwriting its note" do
      user = insert(:user)
      insert(:profile, user: user, contacts_enabled: true)

      insert(:contact,
        organizer_user: user,
        email: "jane@example.com",
        name: "Jane",
        note: "Prefers mornings"
      )

      assert :ok =
               Contacts.capture_from_booking(user.id, %{
                 name: "Jane Booker",
                 email: "jane@example.com"
               })

      assert [contact] = Contacts.list_contacts(user.id)
      assert contact.name == "Jane Booker"
      assert contact.note == "Prefers mornings"
    end
  end
end
