defmodule Tymeslot.MeetingTypes.GroupRegistration do
  @moduledoc """
  Who may book a seat on a group meeting type.

  A group type (`max_participants > 1`) is either open (anyone, up to the
  participant limit) or invite-only: only the addresses in `invited_emails`
  may book a seat, each booking just for themselves (no guests). The mode
  and the list can be changed at any time; a change applies to new bookings
  only, so a seat booked before an address was removed stays booked, the same
  way a lowered participant limit leaves existing seats alone.

  A one-to-one type keeps both fields stored but ignores them, so turning
  group bookings off and on again keeps the list.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  import Ecto.Changeset

  alias Tymeslot.MeetingTypes.MeetingTypeSchema
  alias Tymeslot.Security.FieldValidators.EmailValidator
  alias Tymeslot.Validation.Constraints

  @modes ~w(open invite_only)

  @doc "The registration modes a meeting type may store."
  @spec modes() :: [String.t()]
  def modes, do: @modes

  @doc """
  True when `meeting_type` is a group type that only takes invited bookers.
  """
  @spec invite_only?(MeetingTypeSchema.t() | map() | nil) :: boolean()
  def invite_only?(%{registration_mode: "invite_only"} = meeting_type),
    do: MeetingTypeSchema.group?(meeting_type)

  def invite_only?(_meeting_type), do: false

  @doc """
  Whether `email` may book a seat on `meeting_type`: always for an open or
  one-to-one type, and for an invite-only one only when the address is on its
  list (compared trimmed and case-insensitively).
  """
  @spec invited?(MeetingTypeSchema.t() | map() | nil, term()) :: boolean()
  def invited?(meeting_type, email) do
    if invite_only?(meeting_type),
      do: normalize(email) in (meeting_type.invited_emails || []),
      else: true
  end

  @doc """
  Parses the invite list as the form posts it, one address per line or
  separated by commas or semicolons, into normalised, de-duplicated
  addresses. Blank entries are dropped; malformed ones are kept so the
  changeset can name them.
  """
  @spec parse_list(term()) :: [String.t()]
  def parse_list(value) when is_binary(value) do
    value
    |> String.split(~r/[\s,;]+/u, trim: true)
    |> normalize_all()
  end

  def parse_list(value) when is_list(value), do: normalize_all(value)
  def parse_list(_value), do: []

  @doc """
  Normalises and validates `registration_mode` and `invited_emails` on a
  meeting-type changeset. An invite-only group type needs at least one
  address; every address must be valid.

  The messages are msgids of the `errors` domain, translated where the form
  shows them, like the schema's other validator messages.
  """
  @spec validate(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate(changeset) do
    changeset
    |> update_change(:invited_emails, &normalize_all/1)
    |> validate_inclusion(:registration_mode, @modes)
    |> validate_length(:invited_emails,
      max: Constraints.max_invited_emails(),
      message: dgettext_noop("errors", "can list at most %{count} addresses")
    )
    |> validate_addresses()
    |> validate_list_present()
  end

  defp validate_addresses(changeset) do
    case Enum.reject(get_field(changeset, :invited_emails) || [], &valid_email?/1) do
      [] ->
        changeset

      invalid ->
        add_error(
          changeset,
          :invited_emails,
          dgettext_noop("errors", "contains invalid addresses: %{addresses}"),
          addresses: Enum.join(invalid, ", ")
        )
    end
  end

  defp validate_list_present(changeset) do
    invite_only_group? =
      get_field(changeset, :registration_mode) == "invite_only" and
        MeetingTypeSchema.group?(%MeetingTypeSchema{
          max_participants: get_field(changeset, :max_participants)
        })

    if invite_only_group? and (get_field(changeset, :invited_emails) || []) == [] do
      add_error(
        changeset,
        :invited_emails,
        dgettext_noop("errors", "an invite-only meeting type needs at least one address")
      )
    else
      changeset
    end
  end

  defp normalize_all(emails) when is_list(emails) do
    emails
    |> Enum.map(&normalize/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp normalize_all(_emails), do: []

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(_value), do: ""

  defp valid_email?(email), do: EmailValidator.validate(email) == :ok
end
