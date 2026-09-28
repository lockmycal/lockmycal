defmodule Tymeslot.AppSettings.SiteBannerTranslation do
  @moduledoc """
  Embedded schema for a single per-locale translation of the admin-authored
  site banner message (`Tymeslot.SiteBanner`).

  Same shape as the organiser-content translations
  (`Tymeslot.Profiles.ProfileBookingTextTranslation`,
  `Tymeslot.MeetingTypes.MeetingTypeTranslation`): a blank message falls back
  to the base `site_banner_message` via `Tymeslot.I18n.Resolve.text/4`, and at
  most one row per locale is allowed
  (`Tymeslot.ChangesetValidators.Translations.validate_unique_locales/2`,
  enforced by the owning `AppSettingsSchema`).

  The message goes through the same HTML allow-list as the base message
  (`Tymeslot.Security.SiteBannerScrubber`), since it is rendered raw too.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Ecto.UUID
  alias Tymeslot.ChangesetValidators.Translations
  alias Tymeslot.Security.SiteBannerScrubber

  @type t :: %__MODULE__{
          id: String.t() | nil,
          locale: String.t() | nil,
          message: String.t() | nil
        }

  @fields [:id, :locale, :message]

  # Same cap as the base message (`AppSettingsSchema`).
  @max_message_length 1000

  @primary_key false
  embedded_schema do
    field :id, :string
    field :locale, :string
    field :message, :string
  end

  @doc "Builds a changeset, auto-filling `id` when absent."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(translation, attrs) do
    translation
    |> cast(attrs, @fields, empty_values: [])
    |> update_change(:message, &sanitise/1)
    |> ensure_id()
    |> validate_required([:locale])
    |> Translations.validate_locale()
    |> validate_length(:message, max: @max_message_length)
  end

  defp ensure_id(changeset) do
    case get_field(changeset, :id) do
      nil -> put_change(changeset, :id, UUID.generate())
      _present -> changeset
    end
  end

  # A cleared or markup-only message must become `nil`, not `""`, so
  # `Resolve.text/4` falls back to the base message.
  defp sanitise(nil), do: nil

  defp sanitise(message) do
    case message |> SiteBannerScrubber.sanitize() |> String.trim() do
      "" -> nil
      html -> html
    end
  end
end
