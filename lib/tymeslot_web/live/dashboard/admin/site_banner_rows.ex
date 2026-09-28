defmodule TymeslotWeb.Dashboard.Admin.SiteBannerRows do
  @moduledoc """
  The "Site banner" settings section (`Tymeslot.SiteBanner`): three per-surface
  on/off rows, the message, the background colour, and a live preview.

  Its own section rather than the generic loop in
  `TymeslotWeb.Dashboard.Admin.SettingsView` because the message needs a
  multi-line field, the colour a swatch picker, and the section a preview —
  none of which any other generic row has a use for. Split out of
  `SettingsView` to stay under the module line-count budget, same as
  `TymeslotWeb.Dashboard.Admin.EmailBrandingRows`, and like that module it
  reuses `SettingsView.row_header/1`/`text_input_classes/2` (and here
  `setting_row/1` for the toggles) so every row looks identical.

  Every control writes through the same `"save_setting"`/`"set_setting"`
  events as the rest of the page, handled by
  `TymeslotWeb.Dashboard.Admin.HubComponent`.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias Tymeslot.Locales
  alias Tymeslot.SiteBanner
  alias TymeslotWeb.Components.Dashboard.LocaleTabSwitcher
  alias TymeslotWeb.Components.SiteBanner, as: SiteBannerComponent
  alias TymeslotWeb.Dashboard.Admin.Formatters
  alias TymeslotWeb.Dashboard.Admin.SettingsView

  @toggle_keys [:site_banner_app_enabled, :site_banner_auth_enabled, :site_banner_public_enabled]

  attr :effective_values, :map, required: true
  attr :locale, :string, required: true, doc: "the active language tab of the message row"
  attr :target, :any, required: true

  @spec site_banner_section(map()) :: Phoenix.LiveView.Rendered.t()
  def site_banner_section(assigns) do
    message = Map.fetch!(assigns.effective_values, :site_banner_message).value
    colour = Map.fetch!(assigns.effective_values, :site_banner_colour).value
    translations = Map.fetch!(assigns.effective_values, :site_banner_translations).value

    # The preview follows the active language tab, so an admin sees exactly
    # what a visitor in that language gets, fallback to the base included.
    preview =
      message
      |> SiteBanner.localise(translations, assigns.locale)
      |> SiteBanner.build(colour)

    assigns =
      assigns
      |> assign(:toggle_keys, @toggle_keys)
      |> assign(:message, message)
      |> assign(:translations, translations)
      |> assign(:colour, colour)
      |> assign(:preview, preview)

    ~H"""
    <section id="admin-site-banner-section">
      <.subsection_header
        icon="hero-megaphone"
        title={Formatters.section_label(:site_banner)}
        class="mb-3"
      />

      <div class="card-glass p-0! overflow-hidden divide-y divide-neutral-100 dark:divide-twilight-indigo-800">
        <div class="px-8 py-6">
          <p class="text-token-xs font-black uppercase tracking-wider text-neutral-500 mb-3">
            {dgettext("dashboard_admin", "Preview")}
          </p>
          <div class="rounded-token-lg overflow-hidden border-2 border-neutral-200 dark:border-twilight-indigo-700">
            <SiteBannerComponent.site_banner
              :if={@preview}
              banner={@preview}
              preview={true}
              id="admin-site-banner-preview"
            />
            <p
              :if={!@preview}
              class="px-4 py-3 text-token-sm text-neutral-500 dark:text-neutral-300 text-center"
            >
              {dgettext("dashboard_admin", "Set a banner message to see a preview.")}
            </p>
          </div>
        </div>

        <.message_row
          message={@message}
          translations={@translations}
          locale={@locale}
          target={@target}
        />
        <.colour_row colour={@colour} target={@target} />

        <SettingsView.setting_row
          :for={key <- @toggle_keys}
          key={key}
          effective_values={@effective_values}
          target={@target}
        />
      </div>
    </section>
    """
  end

  # Language tabs follow the organiser-content translation forms
  # (`BookingTextForm`, the meeting-type form): the default-locale tab edits
  # the base `site_banner_message` through the ordinary `"save_setting"`
  # event, every other tab that locale's row of `site_banner_translations`,
  # with the base message as its placeholder since that is what a blank
  # translation falls back to.
  attr :message, :string, default: nil
  attr :translations, :list, required: true
  attr :locale, :string, required: true
  attr :target, :any, required: true

  defp message_row(assigns) do
    assigns =
      assign(
        assigns,
        :translation,
        Enum.find(assigns.translations, &(&1.locale == assigns.locale))
      )

    ~H"""
    <div id="admin-setting-row-site_banner_message" class="px-8 py-6 space-y-4">
      <SettingsView.row_header key={:site_banner_message} />

      <LocaleTabSwitcher.locale_tab_switcher
        active_value={@locale}
        click_event="switch_site_banner_locale"
        target={@target}
      />

      <form
        :if={@locale == Locales.default_locale()}
        id="admin-setting-form-site_banner_message"
        phx-change="save_setting"
        phx-submit="save_setting"
        phx-target={@target}
        aria-label={
          dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(:site_banner_message))
        }
      >
        <input type="hidden" name="key" value="site_banner_message" />
        <.input
          id="setting-input-site_banner_message"
          type="textarea"
          name="value"
          value={@message || ""}
          rows={3}
          maxlength={1000}
          placeholder={
            dgettext("dashboard_admin", "e.g. Scheduled maintenance on Saturday, 8:00-10:00 UTC.")
          }
          phx-debounce="blur"
          spellcheck="false"
        />
      </form>

      <%!-- Id keyed by locale so switching tabs mounts a fresh textarea
           instead of morphing the previous language's text into it. --%>
      <form
        :if={@locale != Locales.default_locale()}
        id={"admin-site-banner-translation-form-#{@locale}"}
        phx-change="save_site_banner_translation"
        phx-submit="save_site_banner_translation"
        phx-target={@target}
        aria-label={
          dgettext("dashboard_admin", "Set %{name}",
            name: Formatters.humanise(:site_banner_translations)
          )
        }
      >
        <input type="hidden" name="locale" value={@locale} />
        <.input
          id={"setting-input-site_banner_translation-#{@locale}"}
          type="textarea"
          name="value"
          value={(@translation && @translation.message) || ""}
          rows={3}
          maxlength={1000}
          placeholder={@message || ""}
          phx-debounce="blur"
          spellcheck="false"
        />
        <p class="mt-2 text-token-xs text-neutral-500 dark:text-neutral-300 font-medium">
          {dgettext(
            "dashboard_admin",
            "Leave blank to show the default-language message to visitors in this language."
          )}
        </p>
      </form>
    </div>
    """
  end

  # Same swatch + hex pair as the email accent row
  # (`EmailBrandingRows.brand_accent_row/1`): both write the one setting
  # through `"save_setting"`, each debounced to its own blur, and
  # `BlurOnChange` commits a swatch pick immediately.
  attr :colour, :string, default: nil
  attr :target, :any, required: true

  defp colour_row(assigns) do
    assigns = assign(assigns, :default_colour, SiteBanner.default_colour())

    ~H"""
    <div
      id="admin-setting-row-site_banner_colour"
      class="px-8 py-6 flex items-start justify-between gap-6 flex-wrap sm:flex-nowrap"
    >
      <SettingsView.row_header key={:site_banner_colour} />

      <div class="flex items-center gap-2 shrink-0">
        <form
          id="admin-setting-form-site_banner_colour"
          phx-change="save_setting"
          phx-target={@target}
          class="flex items-center"
        >
          <input type="hidden" name="key" value="site_banner_colour" />
          <input
            id="setting-swatch-site_banner_colour"
            type="color"
            name="value"
            value={@colour || @default_colour}
            phx-debounce="blur"
            phx-hook="BlurOnChange"
            aria-label={dgettext("dashboard_admin", "Pick a colour")}
            class="h-9 w-12 rounded-token-lg border-2 border-neutral-300 bg-white p-1 cursor-pointer"
          />
        </form>

        <form
          id="admin-setting-hex-form-site_banner_colour"
          phx-change="save_setting"
          phx-submit="save_setting"
          phx-target={@target}
          class="flex items-center"
          aria-label={
            dgettext("dashboard_admin", "Set %{name}", name: Formatters.humanise(:site_banner_colour))
          }
        >
          <input type="hidden" name="key" value="site_banner_colour" />
          <input
            id="setting-input-site_banner_colour"
            type="text"
            name="value"
            value={@colour || ""}
            placeholder={@default_colour}
            spellcheck="false"
            phx-debounce="blur"
            class={SettingsView.text_input_classes("w-32 font-mono", false)}
          />
        </form>
      </div>
    </div>
    """
  end
end
