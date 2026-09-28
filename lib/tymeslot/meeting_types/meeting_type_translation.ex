defmodule Tymeslot.MeetingTypes.MeetingTypeTranslation do
  @moduledoc """
  Embedded schema for a single per-locale translation of a meeting type's
  organizer-authored `name`/`description`.

  A row may translate just one of the two fields — the other falls back to
  the base value via `Tymeslot.I18n.Resolve.text/4` — so only `:locale` is
  required. At most one row per locale is allowed
  (`Tymeslot.ChangesetValidators.Translations.validate_unique_locales/2`,
  enforced by the owning `MeetingTypeSchema`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ecto.UUID
  alias Tymeslot.ChangesetValidators.Translations
  alias Tymeslot.Validation.Constraints

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :id, :string
    field :locale, :string
    field :name, :string
    field :description, :string
  end

  @doc "Builds a changeset, auto-filling `id` when absent."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [:id, :locale, :name, :description], empty_values: [])
    |> normalize_blanks()
    |> ensure_id()
    |> validate_required([:locale])
    |> Translations.validate_locale()
    |> validate_length(:name, max: Constraints.name_length_range().last)
    |> validate_length(:description, max: Constraints.description_max_length())
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
    |> update_change(:name, &blank_to_nil/1)
    |> update_change(:description, &blank_to_nil/1)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
