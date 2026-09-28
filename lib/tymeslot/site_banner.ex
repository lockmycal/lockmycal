defmodule Tymeslot.SiteBanner do
  @moduledoc """
  The admin-configured information bar shown across the top of the app.

  Configuration lives in `Tymeslot.AppSettings` (admin Settings → General →
  Site banner): one message, one background colour, and an independent
  on/off switch per surface:

    * `:app` — the dashboard, admin panel, and onboarding;
    * `:auth` — sign-in, sign-up, and password-reset pages;
    * `:public` — public booking pages (never inside an iframe embed; the
      layout decides that, since only it knows about the embed request).

  The message may be translated per locale
  (`Tymeslot.AppSettings.SiteBannerTranslation`, the same `embeds_many` +
  `Tymeslot.I18n.Resolve` mechanism as meeting-type and booking-page text);
  a locale without its own translation gets the base message.

  Reads go through `AppSettings.get/1`, which is served from the Application
  env, so rendering the banner on every page load costs no database query.

  This is deliberately separate from `Tymeslot.Announcements`: those are
  code-defined, per-user "what's new" modals with DB-tracked seen state,
  whereas this banner is admin-authored, instance-wide, and has to reach
  anonymous visitors, so its dismissal is remembered per browser instead
  (see `id` below).
  """

  alias Tymeslot.AppSettings
  alias Tymeslot.AppSettings.SiteBannerTranslation
  alias Tymeslot.Emails.Branding
  alias Tymeslot.I18n.Resolve
  alias Tymeslot.Security.SiteBannerScrubber
  alias Tymeslot.Utils.Colour

  @type surface :: :app | :auth | :public

  @type t :: %{
          id: String.t(),
          html: String.t(),
          colour: String.t(),
          text_colour: String.t()
        }

  # The two text colours the banner picks between for legibility: white, and
  # Tailwind's `neutral-900`. Hex rather than a utility class because the
  # background is an arbitrary admin-chosen colour applied inline.
  @light_text "#ffffff"
  @dark_text "#171717"

  @doc """
  Returns the banner to render on `surface` for a viewer in `locale`, or `nil`
  when that surface's switch is off or no base message is set.

  The base message is what switches the banner on: a translation on its own,
  with the base left blank, shows nothing in any language — same as a
  meeting type, whose base name is required and translations only override
  it.
  """
  @spec for_surface(surface(), String.t() | nil) :: t() | nil
  def for_surface(surface, locale) when surface in [:app, :auth, :public] do
    if AppSettings.get(enabled_key(surface)) == true do
      AppSettings.get(:site_banner_message)
      |> localise(AppSettings.get(:site_banner_translations), locale)
      |> build(AppSettings.get(:site_banner_colour))
    end
  end

  @doc """
  The message to show a viewer in `locale`: that locale's translation, or the
  base message when there is none. `nil` when the base message is blank,
  whatever the translations hold (see `for_surface/2`).
  """
  @spec localise(String.t() | nil, [SiteBannerTranslation.t()] | nil, String.t() | nil) ::
          String.t() | nil
  def localise(message, _translations, _locale) when message in [nil, ""], do: nil

  def localise(message, translations, locale),
    do: Resolve.text(translations, locale, :message, message)

  @doc """
  Builds the render data for a message/colour pair, or `nil` for a blank
  message. Public so the admin page can preview unsaved-state values through
  the same code path the live banner uses.

  The message is sanitised again here even though the changeset already
  sanitised it on write: it is rendered as raw HTML, so this is defence in
  depth against a row written by anything other than `AppSettings.update/1`.
  """
  @spec build(String.t() | nil, String.t() | nil) :: t() | nil
  def build(message, colour) do
    html = sanitise(message)

    if html do
      colour = Colour.normalise_hex(colour) || default_colour()

      %{
        id: banner_id(html, colour),
        html: html,
        colour: colour,
        text_colour: text_colour_for(colour)
      }
    end
  end

  @doc """
  The background colour used when the admin has not chosen one: the stock
  brand's deep shade, which carries white text legibly.
  """
  @spec default_colour() :: String.t()
  def default_colour, do: Branding.stock_family().deep

  defp enabled_key(:app), do: :site_banner_app_enabled
  defp enabled_key(:auth), do: :site_banner_auth_enabled
  defp enabled_key(:public), do: :site_banner_public_enabled

  defp sanitise(message) when is_binary(message) do
    case message |> SiteBannerScrubber.sanitize() |> String.trim() do
      "" -> nil
      html -> html
    end
  end

  defp sanitise(_nil), do: nil

  # Whichever of the two text colours contrasts more with the background, so
  # an admin picking a pale colour does not end up with invisible white text.
  defp text_colour_for(colour) do
    if Colour.contrast_ratio(colour, @light_text) >= Colour.contrast_ratio(colour, @dark_text),
      do: @light_text,
      else: @dark_text
  end

  # Content-derived, so the per-browser dismissal (stored client-side under
  # this id) lapses by itself as soon as the admin edits the message or
  # colour, and the new banner is shown to everyone again. Derived from the
  # localised message, so each language's banner is dismissed separately
  # and editing one translation re-shows only that language's banner.
  defp banner_id(html, colour) do
    :sha256
    |> :crypto.hash([html, 0, colour])
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end
end
