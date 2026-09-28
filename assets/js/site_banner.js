// Dismiss the admin-configured site banner (Tymeslot.SiteBanner) for this
// browser. Delegated at the document level because the banner lives in the
// root layout on some pages and inside a LiveView on others, and neither a
// hook nor phx-click can reach a root-layout element.
//
// Dismissal hides the bar with an injected CSS rule rather than removing the
// element: a LiveView-rendered banner would otherwise be re-added by the next
// DOM patch. The layout's inline pre-paint script applies the same rule on
// later page loads (keep the storage key in sync with
// TymeslotWeb.Components.SiteBanner.site_banner_dismissal_script/1). The id is derived
// from the banner's content, so editing the banner shows it again.
//
// Markup contract:
//   data-site-banner="<id>"              the bar itself
//   data-site-banner-dismiss="<id>"      the button that dismisses it
export const SITE_BANNER_STORAGE_KEY = "ts:site-banner-dismissed"

// Banner ids are base64url (see Tymeslot.SiteBanner); anything else is
// ignored rather than interpolated into a CSS selector.
const VALID_ID = /^[A-Za-z0-9_-]+$/

export function hideSiteBanner(id) {
  if (!VALID_ID.test(id)) return

  const style = document.createElement("style")
  style.textContent = `[data-site-banner="${id}"]{display:none!important}`
  document.head.appendChild(style)
}

export function installSiteBannerDismiss() {
  document.addEventListener("click", (event) => {
    const trigger =
      event.target.closest && event.target.closest("[data-site-banner-dismiss]")
    if (!trigger) return

    const id = trigger.getAttribute("data-site-banner-dismiss")
    if (!id || !VALID_ID.test(id)) return

    try {
      window.localStorage.setItem(SITE_BANNER_STORAGE_KEY, id)
    } catch (e) {
      // Storage blocked (private mode, disabled site data): still hide the
      // bar for this page view, it just won't be remembered.
    }
    hideSiteBanner(id)
  })
}
