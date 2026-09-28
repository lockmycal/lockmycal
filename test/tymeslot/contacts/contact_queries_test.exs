defmodule Tymeslot.Contacts.ContactQueriesTest do
  use Tymeslot.DataCase, async: true
  @moduletag :contacts
  @moduletag :queries

  import Tymeslot.Factory

  alias Tymeslot.Contacts.ContactQueries

  describe "list_contacts/2" do
    test "lists contacts for the organizer, alphabetically by name" do
      user = insert(:user)
      insert(:contact, organizer_user: user, name: "Zoe")
      insert(:contact, organizer_user: user, name: "Amy")
      insert(:contact, organizer_user: insert(:user), name: "Other user's contact")

      assert [%{name: "Amy"}, %{name: "Zoe"}] = ContactQueries.list_contacts(user.id)
    end

    test "filters by a case-insensitive search on name or email" do
      user = insert(:user)
      insert(:contact, organizer_user: user, name: "Jane Booker", email: "jane@example.com")
      insert(:contact, organizer_user: user, name: "Bob Smith", email: "bob@acme.com")

      assert [%{name: "Jane Booker"}] = ContactQueries.list_contacts(user.id, search: "jane")
      assert [%{name: "Bob Smith"}] = ContactQueries.list_contacts(user.id, search: "acme")
      assert [] = ContactQueries.list_contacts(user.id, search: "nonexistent")
    end

    test "treats a literal _ in the search term as a literal character, not an any-char wildcard" do
      user = insert(:user)
      insert(:contact, organizer_user: user, name: "Underscore", email: "j_hn@example.com")
      insert(:contact, organizer_user: user, name: "Unrelated", email: "john@example.com")

      # Unescaped, "_" matches any single character — "john" would also match.
      assert [%{name: "Underscore"}] = ContactQueries.list_contacts(user.id, search: "j_hn")
    end

    test "treats a literal % in the search term as a literal character, not a zero-or-more wildcard" do
      user = insert(:user)
      insert(:contact, organizer_user: user, name: "50% Off Deal")
      insert(:contact, organizer_user: user, name: "50XX Off Deal")

      # Unescaped, "%" matches zero or more characters — "50XX Off Deal" would also match.
      assert [%{name: "50% Off Deal"}] = ContactQueries.list_contacts(user.id, search: "50% Off")
    end

    test "opts[:limit] caps the result at the database instead of fetching every match" do
      user = insert(:user)

      for name <- ["Amy", "Bob", "Cid", "Dee", "Eve"],
          do: insert(:contact, organizer_user: user, name: name)

      assert [%{name: "Amy"}, %{name: "Bob"}] = ContactQueries.list_contacts(user.id, limit: 2)
    end

    test "no limit returns every match, same as before opts[:limit] existed" do
      user = insert(:user)
      for name <- ["Amy", "Bob", "Cid"], do: insert(:contact, organizer_user: user, name: name)

      assert length(ContactQueries.list_contacts(user.id)) == 3
    end
  end

  describe "get_contact/2" do
    test "returns the contact when it belongs to the organizer" do
      user = insert(:user)
      contact = insert(:contact, organizer_user: user)

      assert {:ok, found} = ContactQueries.get_contact(contact.id, user.id)
      assert found.id == contact.id
    end

    test "returns :not_found for another organizer's contact" do
      contact = insert(:contact)
      other_user = insert(:user)

      assert {:error, :not_found} = ContactQueries.get_contact(contact.id, other_user.id)
    end
  end

  describe "upsert_contact_from_booking/2" do
    test "creates a new contact when none exists for the email yet" do
      user = insert(:user)

      assert {:ok, contact} =
               ContactQueries.upsert_contact_from_booking(user.id, %{
                 name: "Jane Booker",
                 email: "jane@example.com",
                 phone: "555-1234",
                 company: "Acme"
               })

      assert contact.name == "Jane Booker"
      assert contact.company == "Acme"
    end

    test "updates name/phone/company on repeat booking from the same email, keeping the note" do
      user = insert(:user)

      contact =
        insert(:contact,
          organizer_user: user,
          name: "Jane",
          email: "jane@example.com",
          company: "Old Co",
          note: "Wrote this by hand"
        )

      assert {:ok, updated} =
               ContactQueries.upsert_contact_from_booking(user.id, %{
                 name: "Jane Booker",
                 email: "jane@example.com",
                 phone: "555-9999",
                 company: "New Co"
               })

      assert updated.id == contact.id
      assert updated.name == "Jane Booker"
      assert updated.company == "New Co"
      assert updated.phone == "555-9999"
      assert updated.note == "Wrote this by hand"
    end

    test "a repeat booking with different email casing updates the same contact instead of duplicating it" do
      user = insert(:user)

      contact =
        insert(:contact,
          organizer_user: user,
          name: "Jane",
          email: "jane@example.com",
          note: "Wrote this by hand"
        )

      assert {:ok, updated} =
               ContactQueries.upsert_contact_from_booking(user.id, %{
                 name: "Jane Booker",
                 email: "Jane@Example.com"
               })

      assert updated.id == contact.id
      assert updated.email == "jane@example.com"
      assert updated.note == "Wrote this by hand"
      assert [_only_one] = ContactQueries.list_contacts(user.id)
    end

    test "the same email creates separate contacts for different organizers" do
      contact = insert(:contact, email: "shared@example.com")
      other_user = insert(:user)

      assert {:ok, other_contact} =
               ContactQueries.upsert_contact_from_booking(other_user.id, %{
                 name: "Someone Else",
                 email: "shared@example.com"
               })

      assert other_contact.id != contact.id
    end
  end

  describe "delete_contact/1" do
    test "deletes the contact" do
      contact = insert(:contact)

      assert {:ok, _deleted} = ContactQueries.delete_contact(contact)

      assert {:error, :not_found} =
               ContactQueries.get_contact(contact.id, contact.organizer_user_id)
    end
  end
end
