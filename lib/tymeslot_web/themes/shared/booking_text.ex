defmodule TymeslotWeb.Themes.Shared.BookingText do
  @moduledoc """
  Resolves the booking page's introductory copy: the organiser's own wording
  when they have turned the customisation on, the theme's translated default
  otherwise.

  Every theme with an overview step renders the same three slots, so the
  resolution lives here rather than in each theme. The heading default differs
  by theme (Quill opens with a generic greeting, Rhythm names the organiser)
  and is therefore keyed by theme; the greeting and instruction defaults are
  identical everywhere.

  The defaults live here rather than inline in each theme because the dashboard
  has to show an organiser what a single custom heading replaces in *both*
  themes, which is cross-theme knowledge no individual theme may hold. Themes
  still own the name they introduce themselves by, and pass it in: Rhythm
  substitutes a friendly word when the profile has no name, Quill drops the
  greeting instead.

  The organiser's own wording may itself be translated per-locale (see
  `Tymeslot.Profiles.ProfileBookingTextTranslation`); `custom/3` resolves that
  against the booker's own `locale` before falling back to the base string.
  The theme's own defaults below stay untranslated per-locale, since they are
  already Gettext strings, not organiser-authored text.
  """

  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.I18n.Resolve
  alias Tymeslot.Profiles.ProfileSchema

  @type theme_key :: :quill | :rhythm

  @doc """
  The page's introductory heading, given the theme whose default applies, the
  name that theme introduces the organiser by, and the booker's `locale`.
  """
  @spec heading(ProfileSchema.t() | nil, theme_key(), String.t() | nil, String.t()) :: String.t()
  def heading(profile, theme_key, name, locale),
    do: custom(profile, :booking_heading, locale) || default_heading(theme_key, name)

  @doc """
  The greeting line. `nil` when there is no name to introduce and no custom
  wording, which drops the line rather than rendering half a sentence.
  """
  @spec greeting(ProfileSchema.t() | nil, String.t() | nil, String.t()) :: String.t() | nil
  def greeting(profile, name, locale),
    do: custom(profile, :booking_greeting, locale) || default_greeting(name)

  @doc """
  The line telling the visitor what to do next.
  """
  @spec instruction(ProfileSchema.t() | nil, String.t()) :: String.t()
  def instruction(profile, locale),
    do: custom(profile, :booking_instruction, locale) || default_instruction()

  @doc """
  The heading a theme shows when the organiser has not supplied one.
  """
  @spec default_heading(theme_key(), String.t() | nil) :: String.t()
  def default_heading(:rhythm, name),
    do: dgettext("booking", "Schedule with %{name}", name: name)

  def default_heading(_theme_key, _name), do: dgettext("booking", "Let's Connect!")

  @doc """
  The greeting shown when the organiser has not supplied one, or `nil` when
  there is no name to introduce.
  """
  @spec default_greeting(String.t() | nil) :: String.t() | nil
  def default_greeting(nil), do: nil
  def default_greeting(name), do: dgettext("booking", "Hi! I'm %{name}.", name: name)

  @doc """
  A greeting to start the organiser off with when they switch the customisation
  on, which unlike `default_greeting/1` is never `nil`.

  Turning the customisation on requires all three lines to be filled, so a
  profile with no name still needs something to seed the field with. The public
  page keeps dropping the line in that case; this is only ever a starting point
  in the dashboard.
  """
  @spec seed_greeting(String.t() | nil) :: String.t()
  def seed_greeting(nil), do: dgettext("booking", "Hi there!")
  def seed_greeting(name), do: default_greeting(name)

  @doc """
  The instruction shown when the organiser has not supplied one.
  """
  @spec default_instruction() :: String.t()
  def default_instruction, do: dgettext("booking", "Pick an option below.")

  defp custom(%{booking_text_enabled: true} = profile, field, locale) do
    Resolve.text(profile.booking_text_translations, locale, field, Map.get(profile, field))
  end

  defp custom(_profile, _field, _locale), do: nil
end
