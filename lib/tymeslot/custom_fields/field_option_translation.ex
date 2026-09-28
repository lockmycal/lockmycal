defmodule Tymeslot.CustomFields.FieldOptionTranslation do
  @moduledoc """
  Embedded schema for a single per-locale translation of a select question's
  option `label`. Falls back to the option's base label via
  `Tymeslot.I18n.Resolve.text/4` when the row's label is blank.

  At most one row per locale is allowed
  (`Tymeslot.ChangesetValidators.Translations.validate_unique_locales/2`,
  enforced by the owning `FieldOption`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Tymeslot.ChangesetValidators.Translations

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :locale, :string
    field :label, :string
  end

  @doc "Builds a changeset. A cleared label becomes `nil`, so the base label is used."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(translation, attrs) do
    translation
    |> cast(attrs, [:locale, :label], empty_values: [])
    |> update_change(:label, &blank_to_nil/1)
    |> validate_required([:locale])
    |> Translations.validate_locale()
    |> validate_length(:label, max: 80)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
