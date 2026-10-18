defmodule Tymeslot.MeetingTypes.Localized do
  @moduledoc """
  A meeting type's name and description in a given locale: the host's own
  translation for that locale, else the base text. What the dashboard shows the
  host, as the booking page does for a guest (`Tymeslot.I18n.Resolve`).
  """

  alias Tymeslot.I18n.Resolve
  alias Tymeslot.MeetingTypes.MeetingTypeSchema

  @doc """
  The meeting type's name in `locale`. A map without `translations` (a plain
  summary of a type) has none to apply.
  """
  @spec name(MeetingTypeSchema.t(), String.t()) :: String.t() | nil
  def name(meeting_type, locale),
    do: Resolve.text(Map.get(meeting_type, :translations), locale, :name, meeting_type.name)

  @doc "The meeting type's description in `locale`; see `name/2`."
  @spec description(MeetingTypeSchema.t(), String.t()) :: String.t() | nil
  def description(meeting_type, locale) do
    Resolve.text(
      Map.get(meeting_type, :translations),
      locale,
      :description,
      meeting_type.description
    )
  end
end
