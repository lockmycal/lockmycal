defmodule Tymeslot.Security.AuditLog.AuditEventSchema do
  @moduledoc """
  One persisted security event (see `Tymeslot.Security.AuditLog`).

  `user_id` is the account the event is about and `actor_user_id` who caused
  it when that is someone else (an admin). Neither is a foreign key: the audit
  trail outlives the accounts it describes. `email` is the full address the
  event names, for admins only; `email_masked` is its masked form, the only one
  rows recorded before `email` existed have. Other values arrive already
  redacted by `Tymeslot.Security.SecurityLogger`.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          event_type: String.t() | nil,
          user_id: integer() | nil,
          actor_user_id: integer() | nil,
          email: String.t() | nil,
          email_masked: String.t() | nil,
          ip_address: String.t() | nil,
          user_agent: String.t() | nil,
          session_id: String.t() | nil,
          provider: String.t() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  @fields [
    :event_type,
    :user_id,
    :actor_user_id,
    :email,
    :email_masked,
    :ip_address,
    :user_agent,
    :session_id,
    :provider,
    :metadata
  ]

  schema "audit_events" do
    field(:event_type, :string)
    field(:user_id, :integer)
    field(:actor_user_id, :integer)
    field(:email, :string)
    field(:email_masked, :string)
    field(:ip_address, :string)
    field(:user_agent, :string)
    field(:session_id, :string)
    field(:provider, :string)
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required([:event_type])
    |> validate_length(:event_type, max: 255)
    |> validate_length(:user_agent, max: 200)
  end
end
