defmodule TymeslotWeb.Components.SiteBanner do
  @moduledoc """
  Renders the admin-configured site banner (`Tymeslot.SiteBanner`).

  The bar is styled inline rather than with utility classes: it appears both
  on app pages (`app.css`) and on public booking pages, which load only their
  theme's own CSS build, so an inline style is the one thing guaranteed to
  look the same on both. (The same reason the `noscript` warning in
  `TymeslotWeb.Layouts` is inline-styled.)

  Dismissal is per browser and purely client-side — see
  `assets/js/site_banner.js` for the click handler and `site_banner_dismissal_script/1`
  for the pre-paint half that keeps a dismissed bar from flashing on later
  page loads.
  """

  use TymeslotWeb, :html
  use Gettext, backend: TymeslotWeb.Gettext

  @doc """
  The bar itself. Renders nothing for a `nil` banner.

  `preview` renders the admin-page preview: no dismiss button and no
  `data-site-banner` id, so a dismissal of the live banner does not also hide
  its preview.
  """
  attr :banner, :map, default: nil, doc: "a `Tymeslot.SiteBanner.t()` or nil"
  attr :preview, :boolean, default: false
  attr :id, :string, default: "site-banner"

  @spec site_banner(map()) :: Phoenix.LiveView.Rendered.t()
  def site_banner(%{banner: nil} = assigns), do: ~H""

  def site_banner(assigns) do
    ~H"""
    <div
      id={@id}
      data-site-banner={!@preview && @banner.id}
      role="region"
      aria-label={dgettext("common", "Announcement")}
      style={"display: flex; align-items: center; gap: 12px; padding: 8px 16px; font-size: 14px; line-height: 1.4; font-weight: 500; flex-shrink: 0; background-color: #{@banner.colour}; color: #{@banner.text_colour};"}
    >
      <style>
        [data-site-banner-message] a { color: inherit; text-decoration: underline; }
      </style>
      <div data-site-banner-message style="flex: 1; min-width: 0; text-align: center;">
        {raw(@banner.html)}
      </div>
      <button
        :if={!@preview}
        type="button"
        data-site-banner-dismiss={@banner.id}
        aria-label={dgettext("common", "Dismiss announcement")}
        title={dgettext("common", "Dismiss announcement")}
        style="flex-shrink: 0; background: transparent; border: 0; color: inherit; cursor: pointer; font-size: 20px; line-height: 1; padding: 0 4px; opacity: 0.8;"
      >
        &times;
      </button>
    </div>
    """
  end

  @doc """
  Pre-paint half of the per-browser dismissal: an inline script for the
  document `<head>` that hides a previously dismissed banner before the first
  paint, so it never flashes on screen. Renders nothing unless `banner` is
  set. Keep the storage key, id pattern, and rule in sync with
  `assets/js/site_banner.js`.
  """
  attr :banner, :map, default: nil
  attr :nonce, :string, default: nil

  @spec site_banner_dismissal_script(map()) :: Phoenix.LiveView.Rendered.t()
  def site_banner_dismissal_script(%{banner: nil} = assigns), do: ~H""

  def site_banner_dismissal_script(assigns) do
    ~H"""
    <script nonce={@nonce}>
      (function () {
        try {
          var id = window.localStorage.getItem("ts:site-banner-dismissed");
          if (id && /^[A-Za-z0-9_-]+$/.test(id)) {
            var style = document.createElement("style");
            style.textContent = '[data-site-banner="' + id + '"]{display:none!important}';
            document.head.appendChild(style);
          }
        } catch (e) {}
      })();
    </script>
    """
  end
end
