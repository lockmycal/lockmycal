defmodule TymeslotWeb.Dashboard.Admin.EmailBrandingRows do
  @moduledoc """
  The two "Email branding" settings rows that don't fit the generic
  key-to-control mapping in `TymeslotWeb.Dashboard.Admin.SettingsView`: the
  accent colour picker (needs derived preview/contrast data no other row has
  a use for) and the logo upload (takes a file upload instead of a form
  field). Split out of `SettingsView` purely to stay under the project's
  per-module line-count budget — both are called from
  `SettingsView.email_branding_section/1`, and both reuse `SettingsView`'s
  own `row_header/1` and `text_input_classes/2` so they stay visually
  identical to the generic rows.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  alias TymeslotWeb.Dashboard.Admin.Formatters
  alias TymeslotWeb.Dashboard.Admin.SettingsView

  # Both the swatch and the hex field write `email_brand_accent` straight
  # through the same `"save_setting"` event every other typed setting uses,
  # each debounced to its own blur. A single LiveView connection processes
  # events strictly in the order the admin triggered them, so whichever
  # control they touched last determines the final value — same as any other
  # setting on this page, not a race. `BlurOnChange` on the swatch blurs it
  # the instant a colour commits (native colour pickers otherwise leave the
  # swatch focused after closing), so the pick both saves and mirrors into
  # the hex field immediately instead of waiting on an unrelated blur.
  attr :effective, :map, required: true
  attr :stock_accent, :string, required: true
  attr :accent_preview, :map, default: nil
  attr :target, :any, required: true

  @spec brand_accent_row(map()) :: Phoenix.LiveView.Rendered.t()
  def brand_accent_row(assigns) do
    assigns =
      assigns
      |> assign(:current, assigns.effective.value || assigns.stock_accent)
      |> assign(:hex_value, assigns.effective.value || "")

    ~H"""
    <div class="px-8 py-6 flex items-start justify-between gap-6 flex-wrap sm:flex-nowrap">
      <SettingsView.row_header key={:email_brand_accent} />

      <div class="flex flex-col items-end gap-2 shrink-0">
        <div class="flex items-center gap-2">
          <form
            id="admin-setting-form-email_brand_accent"
            phx-change="save_setting"
            phx-target={@target}
            class="flex items-center"
          >
            <input type="hidden" name="key" value="email_brand_accent" />
            <input
              id="setting-swatch-email_brand_accent"
              type="color"
              name="value"
              value={@current}
              phx-debounce="blur"
              phx-hook="BlurOnChange"
              aria-label={dgettext("dashboard_admin", "Pick a colour")}
              aria-describedby="email-brand-accent-feedback"
              class="h-9 w-12 rounded-token-lg border-2 border-neutral-300 bg-white p-1 cursor-pointer"
            />
          </form>

          <form
            id="admin-setting-hex-form-email_brand_accent"
            phx-change="save_setting"
            phx-submit="save_setting"
            phx-target={@target}
            class="flex items-center"
            aria-label={
              dgettext("dashboard_admin", "Set %{name}",
                name: Formatters.humanise(:email_brand_accent)
              )
            }
          >
            <input type="hidden" name="key" value="email_brand_accent" />
            <input
              id="setting-input-email_brand_accent"
              type="text"
              name="value"
              value={@hex_value}
              placeholder={@stock_accent}
              spellcheck="false"
              phx-debounce="blur"
              aria-describedby="email-brand-accent-feedback"
              class={SettingsView.text_input_classes("w-32 font-mono", false)}
            />
          </form>
        </div>

        <div id="email-brand-accent-feedback" aria-live="polite">
          <.contrast_warning
            :if={@accent_preview != nil and @accent_preview.low_contrast?}
            ratio={@accent_preview.contrast}
          />
        </div>
      </div>
    </div>
    """
  end

  # The email logo is not a plain form field: it takes an upload, so it is
  # its own row rather than a `setting_control` kind, reading the LiveView's
  # upload state and the currently stored logo from its own attrs.
  #
  # The visible control is a plain file input, not `live_file_input`: the hook
  # rasterises whatever the admin picked to a PNG in the browser and hands the
  # result to the uploader via `this.upload/2`. That keeps SVG and WebP sources
  # working without a rasteriser on the server, and means the only bytes that
  # ever reach the server are a PNG — which `Branding.store_logo/1` re-validates,
  # because a client-side conversion is a convenience, not a trust boundary.
  attr :logo_url, :string, default: nil
  attr :upload, :map, required: true
  attr :errors, :list, default: []
  # What the file picker offers, not what is uploaded: the browser rasterises
  # whatever the admin picked to a PNG before it reaches the server.
  attr :accept, :string, default: "image/png,image/jpeg,image/webp,image/svg+xml"
  # 2x the 150px the email displays the logo at, so it stays sharp on retina
  # without carrying a needlessly large attachment on every send.
  attr :render_width, :integer, default: 300
  # A 300px-wide PNG lands far under this; the cap is a backstop against a
  # client that ignores the hook and posts something else entirely. Sourced
  # from the caller's `@logo_max_bytes`, the single place the limit is
  # declared - it also feeds `allow_upload/3` and the hook's own client-side
  # size guard, so there is exactly one number to keep in sync.
  attr :max_bytes, :integer, required: true
  attr :target, :any, required: true

  @spec email_logo_row(map()) :: Phoenix.LiveView.Rendered.t()
  def email_logo_row(assigns) do
    ~H"""
    <div class="px-8 py-6 flex items-start justify-between gap-6 flex-wrap sm:flex-nowrap">
      <SettingsView.row_header key={:email_logo_path} />

      <div class="flex flex-col items-end gap-3 shrink-0">
        <div
          :if={@logo_url}
          class="flex items-center gap-3 px-4 py-3 rounded-token-xl bg-neutral-50 border-2 border-neutral-300"
        >
          <img
            src={@logo_url}
            alt={dgettext("dashboard_admin", "Current email logo")}
            class="h-10 w-auto max-w-[150px] object-contain"
          />
          <button
            type="button"
            phx-click="remove_email_logo"
            phx-target={@target}
            class="text-token-xs font-black uppercase tracking-wider text-red-600 hover:text-red-700 cursor-pointer"
          >
            {dgettext("dashboard_admin", "Remove")}
          </button>
        </div>

        <form id="admin-email-logo-form" phx-change="validate_email_logo" phx-target={@target}>
          <%!--
            The uploader input is present but hidden. `this.upload/2` in the hook
            resolves the uploader by looking up upload inputs in the DOM by name,
            so it has to exist even though the admin never interacts with it.
          --%>
          <.live_file_input upload={@upload} class="hidden" />

          <label class="inline-flex items-center gap-2 px-3 py-1.5 rounded-token-lg border-2 border-neutral-300 bg-white dark:bg-twilight-indigo-950 text-token-xs font-black uppercase tracking-wider text-neutral-700 dark:text-neutral-200 hover:bg-neutral-50 cursor-pointer focus-within:outline-hidden focus-within:ring-2 focus-within:ring-primary-500 focus-within:ring-offset-2">
            <.icon name="hero-arrow-up-tray-mini" class="w-4 h-4" />
            {if @logo_url,
              do: dgettext("dashboard_admin", "Replace"),
              else: dgettext("dashboard_admin", "Upload")}
            <input
              id="email-logo-picker"
              type="file"
              accept={@accept}
              class="sr-only"
              phx-hook="EmailLogoUpload"
              phx-target={@target}
              phx-update="ignore"
              aria-describedby="email-logo-errors"
              data-upload-name={@upload.name}
              data-render-width={@render_width}
              data-max-bytes={@max_bytes}
            />
          </label>
        </form>

        <div id="email-logo-errors" aria-live="polite">
          <p
            :for={message <- @errors}
            class="max-w-[16rem] text-token-xs font-bold text-red-600 text-right"
          >
            {message}
          </p>
        </div>
      </div>
    </div>
    """
  end

  attr :ratio, :float, required: true

  defp contrast_warning(assigns) do
    ~H"""
    <p class="flex items-start gap-1.5 max-w-[16rem] text-token-xs font-bold text-amber-700 text-right">
      <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4 shrink-0 mt-px" />
      <span>
        {dgettext(
          "dashboard_admin",
          "White button text on this colour has a contrast of only %{ratio}:1. Buttons may be hard to read.",
          ratio: :erlang.float_to_binary(@ratio, decimals: 1)
        )}
      </span>
    </p>
    """
  end
end
