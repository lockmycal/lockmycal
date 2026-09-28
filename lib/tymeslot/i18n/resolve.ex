defmodule Tymeslot.I18n.Resolve do
  @moduledoc """
  Resolves organizer-authored, per-locale translation overrides against a
  base value.

  Used by every render/booking-time call site that shows organizer-authored
  text (meeting-type name/description, the profile's custom booking-page
  text) to a booker in their own locale, on top of the `embeds_many`
  translation lists defined by `Tymeslot.MeetingTypes.MeetingTypeTranslation`
  and `Tymeslot.Profiles.ProfileBookingTextTranslation`.
  """

  @doc """
  Returns the translated value of `field` for `locale`, falling back to
  `fallback` when there is no matching row or the row's own `field` is
  blank (`nil`/`""`) — an organizer may translate only some of a record's
  fields for a given locale and leave the rest on the base text.
  """
  @spec text([struct()] | nil, String.t(), atom(), value) :: value when value: String.t() | nil
  def text(translations, locale, field, fallback)

  def text(translations, locale, field, fallback) when is_list(translations) do
    case Enum.find(translations, &(&1.locale == locale)) do
      nil ->
        fallback

      row ->
        case Map.get(row, field) do
          value when value in [nil, ""] -> fallback
          value -> value
        end
    end
  end

  def text(_translations, _locale, _field, fallback), do: fallback
end
