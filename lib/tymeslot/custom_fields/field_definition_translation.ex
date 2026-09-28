defmodule Tymeslot.CustomFields.FieldDefinitionTranslation do
  @moduledoc """
  Embedded schema for a single per-locale translation of a custom
  question's organizer-authored `label`/`help_text`/`body`.

  A row may translate just one of the three fields — the others fall back
  to the base value via `Tymeslot.I18n.Resolve.text/4` — so only `:locale`
  is required. `body` only matters for the `"note"` question type, but is
  not itself type-checked here; an unused translated body is simply never
  read. Option labels of `single_select`/`multi_select` questions are
  translated on the option itself (`Tymeslot.CustomFields.FieldOptionTranslation`).

  At most one row per locale is allowed
  (`Tymeslot.ChangesetValidators.Translations.validate_unique_locales/2`,
  enforced by the owning `FieldDefinition`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ecto.UUID
  alias Tymeslot.ChangesetValidators.Translations

  @type t :: %__MODULE__{}

  @fields [:id, :locale, :label, :help_text, :body]

  @primary_key false
  embedded_schema do
    field :id, :string
    field :locale, :string
    field :label, :string
    field :help_text, :string
    field :body, :string
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
    |> validate_length(:label, max: 120)
    |> validate_length(:help_text, max: 300)
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
    |> update_change(:label, &blank_to_nil/1)
    |> update_change(:help_text, &blank_to_nil/1)
    |> update_change(:body, &blank_to_nil/1)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
