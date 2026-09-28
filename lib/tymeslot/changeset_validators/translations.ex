defmodule Tymeslot.ChangesetValidators.Translations do
  @moduledoc """
  Shared changeset validators for per-locale translation `embeds_many` lists
  (`meeting_types.translations`, `profiles.booking_text_translations`).

  Each translation row is a locale plus a handful of optional overrides for
  the owner's own base fields; `Tymeslot.I18n.Resolve.text/4` reads these
  lists back at render/booking time. This module only validates the rows
  themselves — locale membership and no two rows sharing a locale — leaving
  per-field length/format rules to each embed's own changeset.
  """

  import Ecto.Changeset

  alias Tymeslot.Locales

  @doc """
  Validates that `:locale` is one of `Locales.supported_codes/0`.

  Called from within a translation embed's own `changeset/2`. Uses
  `supported_codes/0`, never `acceptable?/1`, so the dev-only `"pseudo"`
  locale can never be persisted as an organizer-authored translation.
  """
  @spec validate_locale(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_locale(changeset) do
    validate_inclusion(changeset, :locale, Locales.supported_codes())
  end

  @doc """
  Validates that no two rows in the owner's `field` (an `embeds_many` of
  translation rows) share the same `:locale`.

  Called in the *owning* schema's changeset, right after `cast_embed/3`.
  Mirrors `Tymeslot.CustomFields.FieldDefinition`'s private
  `validate_unique_option_keys/1`.
  """
  @spec validate_unique_locales(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  def validate_unique_locales(changeset, field) do
    locales =
      (get_field(changeset, field) || [])
      |> Enum.map(& &1.locale)
      |> Enum.reject(&is_nil/1)

    if locales != Enum.uniq(locales) do
      add_error(changeset, field, "must not contain duplicate locales")
    else
      changeset
    end
  end
end
