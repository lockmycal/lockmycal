defmodule Tymeslot.Contacts.ContactSchema do
  @moduledoc """
  Ecto schema for a contact — a booker whose details were either captured
  automatically from a public booking, or added manually by the organizer.

  One row per unique `email` within an `organizer_user_id` (see the
  `contacts_organizer_email_index` unique index): repeat bookings from the
  same address update the existing row rather than creating a duplicate.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Tymeslot.ChangesetValidators.Email, as: EmailChangeset
  alias Tymeslot.Validation.Constraints

  @type t :: %__MODULE__{
          id: integer() | nil,
          organizer_user_id: integer() | nil,
          name: String.t() | nil,
          email: String.t() | nil,
          phone: String.t() | nil,
          company: String.t() | nil,
          note: String.t() | nil,
          organizer_user: Tymeslot.Auth.UserSchema.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "contacts" do
    field(:name, :string)
    field(:email, :string)
    field(:phone, :string)
    field(:company, :string)
    field(:note, :string)

    belongs_to(:organizer_user, Tymeslot.Auth.UserSchema, foreign_key: :organizer_user_id)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:organizer_user_id, :name, :email]
  @optional_fields [:phone, :company, :note]

  @doc """
  Full changeset — manual create/edit from the Contacts dashboard page.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> update_change(:email, &String.downcase/1)
    |> validate_length(:name, Constraints.name_length_opts())
    |> validate_length(:phone, max: 50)
    |> validate_length(:company, max: 255)
    |> validate_length(:note, max: 2000)
    |> EmailChangeset.validate_email(:email)
    |> foreign_key_constraint(:organizer_user_id)
    |> unique_constraint(:email, name: :contacts_organizer_email_index)
  end

  @doc """
  Capture-path changeset, used when upserting from a new public booking.

  Deliberately excludes `:note` from the castable fields so an automatic
  capture can never clobber a note the organizer wrote by hand.
  """
  @spec capture_changeset(t(), map()) :: Ecto.Changeset.t()
  def capture_changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ [:phone, :company])
    |> validate_required(@required_fields)
    |> update_change(:email, &String.downcase/1)
    |> validate_length(:name, Constraints.name_length_opts())
    |> validate_length(:phone, max: 50)
    |> validate_length(:company, max: 255)
    |> EmailChangeset.validate_email(:email)
    |> foreign_key_constraint(:organizer_user_id)
    |> unique_constraint(:email, name: :contacts_organizer_email_index)
  end
end
