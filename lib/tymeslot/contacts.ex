defmodule Tymeslot.Contacts do
  @moduledoc """
  Context module for contacts — bookers whose details were captured from a
  public booking, or added manually, so the organizer can keep a simple
  address book of the people they meet with.

  Gating is split in two, independent of each other:

    * `:contacts_allowed` (`Tymeslot.Features.check_access/2`) — the
      plan/paid-feature gate. Gates manual CRUD and automatic capture; reads
      are never gated, same as `Tymeslot.Webhooks`.
    * `profile.contacts_enabled` — the organizer's own "Collect contacts?"
      opt-in. Gates *only* automatic capture from new bookings (see
      `capture_from_booking/2`); it never blocks manual CRUD or reading
      contacts already captured.
  """

  require Logger

  alias Tymeslot.Contacts.ContactQueries
  alias Tymeslot.Contacts.ContactSchema
  alias Tymeslot.Contacts.CsvExport
  alias Tymeslot.Features
  alias Tymeslot.Infrastructure.Logging.LogFormat
  alias Tymeslot.Meetings
  alias Tymeslot.Meetings.MeetingSchema
  alias Tymeslot.Pagination.OffsetPage
  alias Tymeslot.Profiles
  alias Tymeslot.Profiles.ProfileSchema

  @doc """
  Lists contacts for an organizer. `opts[:search]` filters by name or email;
  `opts[:limit]` caps the result at the database.
  """
  @spec list_contacts(integer(), keyword()) :: [ContactSchema.t()]
  def list_contacts(user_id, opts \\ []) do
    ContactQueries.list_contacts(user_id, opts)
  end

  @doc """
  One page of `list_contacts/2` (`Tymeslot.Pagination.OffsetPage`), for the
  Contacts dashboard page.
  """
  @spec list_contacts_page(integer(), String.t() | nil, integer(), integer()) ::
          OffsetPage.t(ContactSchema.t())
  def list_contacts_page(user_id, search, page, per_page) do
    user_id
    |> ContactQueries.count_contacts(search)
    |> OffsetPage.fetch(page, per_page, fn limit, offset ->
      ContactQueries.list_contacts(user_id, search: search, limit: limit, offset: offset)
    end)
  end

  @doc """
  Every contact matching `search` (all of them when it is blank), across all
  pages, as a CSV file (`Tymeslot.Contacts.CsvExport`). Not feature-gated,
  same as the other reads.
  """
  @spec export_csv(integer(), String.t() | nil) :: iodata()
  def export_csv(user_id, search) do
    user_id
    |> ContactQueries.list_contacts(search: search)
    |> CsvExport.encode()
  end

  @doc """
  Gets a single contact by ID for a specific organizer.
  """
  @spec get_contact(integer(), integer()) :: {:ok, ContactSchema.t()} | {:error, :not_found}
  def get_contact(id, user_id) do
    ContactQueries.get_contact(id, user_id)
  end

  @doc """
  Creates a contact for a user.
  """
  @spec create_contact(integer(), map()) ::
          {:ok, ContactSchema.t()}
          | {:error, Ecto.Changeset.t() | Features.access_error()}
  def create_contact(user_id, attrs) do
    with :ok <- Features.check_access(user_id, :contacts_allowed) do
      attrs
      |> Map.put(:organizer_user_id, user_id)
      |> ContactQueries.insert_contact()
    end
  end

  @doc """
  Updates a contact.
  """
  @spec update_contact(ContactSchema.t(), map()) ::
          {:ok, ContactSchema.t()}
          | {:error, Ecto.Changeset.t() | Features.access_error()}
  def update_contact(%ContactSchema{} = contact, attrs) do
    with :ok <- Features.check_access(contact.organizer_user_id, :contacts_allowed) do
      ContactQueries.update_contact(contact, attrs)
    end
  end

  @doc """
  Deletes a contact. Not feature-gated — an organizer can always remove
  their own data regardless of plan status.
  """
  @spec delete_contact(ContactSchema.t()) ::
          {:ok, ContactSchema.t()} | {:error, Ecto.Changeset.t()}
  def delete_contact(%ContactSchema{} = contact) do
    ContactQueries.delete_contact(contact)
  end

  @doc """
  Lists the meetings a contact has booked with this organizer, for the
  "view meetings" action.
  """
  @spec list_meetings_for_contact(integer(), String.t()) :: [MeetingSchema.t()]
  def list_meetings_for_contact(organizer_user_id, email) do
    Meetings.list_meetings_for_contact(organizer_user_id, email)
  end

  @doc """
  Captures or refreshes a contact from a newly created public booking.

  Only runs when the organizer has both plan access (`:contacts_allowed`)
  and has opted in via `profile.contacts_enabled` — otherwise a no-op.
  Never raises and never returns an error to the caller: a capture failure
  must not affect the booking it was triggered by. Every skip/failure path
  is logged instead.
  """
  @spec capture_from_booking(integer(), map()) :: :ok
  def capture_from_booking(organizer_user_id, attendee_attrs) do
    with true <- collecting_enabled?(organizer_user_id),
         :ok <- Features.check_access(organizer_user_id, :contacts_allowed),
         {:ok, _contact} <-
           ContactQueries.upsert_contact_from_booking(organizer_user_id, attendee_attrs) do
      :ok
    else
      false ->
        :ok

      {:error, :feature_disabled} ->
        :ok

      {:error, reason} ->
        Logger.warning("Contact capture skipped",
          organizer_user_id: organizer_user_id,
          reason: LogFormat.reason(reason)
        )

        :ok
    end
  end

  defp collecting_enabled?(organizer_user_id) do
    case Profiles.get_profile(organizer_user_id) do
      %ProfileSchema{contacts_enabled: true} -> true
      _other -> false
    end
  end
end
