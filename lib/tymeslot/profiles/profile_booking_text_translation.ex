defmodule Tymeslot.Profiles.ProfileBookingTextTranslation do
  @moduledoc """
  Embedded schema for a single per-locale translation of a profile's custom
  booking-page welcome text (`booking_heading`/`booking_greeting`/
  `booking_instruction`).

  Unlike the base `booking_text_changeset/2`, a row does **not** require all
  three fields together — a partial row is valid, and each blank field falls
  back to the base value via `Tymeslot.I18n.Resolve.text/4`. At most one row
  per locale is allowed
  (`Tymeslot.ChangesetValidators.Translations.validate_unique_locales/2`,
  enforced by the owning `ProfileSchema`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ecto.UUID
  alias Tymeslot.ChangesetValidators.Translations
  alias Tymeslot.Validation.Constraints

  @type t :: %__MODULE__{}

  @fields [:id, :locale, :booking_heading, :booking_greeting, :booking_instruction]

  @primary_key false
  embedded_schema do
    field :id, :string
    field :locale, :string
    field :booking_heading, :string
    field :booking_greeting, :string
    field :booking_instruction, :string
  end

  @doc "Builds a changeset, auto-filling `id` when absent."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(translation, attrs) do
    translation
    |> cast(attrs, @fields, empty_values: [])
    |> normalize_blanks()
    |> ensure_id()
    |> validate_required([:locale])
    |> Translations.validate_locale()
    |> validate_length(:booking_heading, max: Constraints.booking_heading_max_length())
    |> validate_length(:booking_greeting, max: Constraints.booking_welcome_line_max_length())
    |> validate_length(:booking_instruction, max: Constraints.booking_welcome_line_max_length())
  end

  defp ensure_id(changeset) do
    case get_field(changeset, :id) do
      nil -> put_change(changeset, :id, UUID.generate())
      _present -> changeset
    end
  end

  # A cleared field must become `nil`, not `""`, so `Resolve.text/4` falls
  # back to the base value instead of rendering an empty string.
  defp normalize_blanks(changeset) do
    changeset
    |> update_change(:booking_heading, &blank_to_nil/1)
    |> update_change(:booking_greeting, &blank_to_nil/1)
    |> update_change(:booking_instruction, &blank_to_nil/1)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
