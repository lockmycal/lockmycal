/**
 * AppearanceToggle hook
 *
 * The <html> class is set server-side on first render (see root.html.heex +
 * AppAppearanceHook), but that layout is rendered once per HTTP request and
 * never re-patched by LiveView — a click on a toggle only updates the
 * component's own DOM, so without this hook the saved preference wouldn't
 * visibly apply until the next full page load.
 *
 * Mounted on a wrapper containing `button[phx-value-option]` children (Profile
 * Settings' Light/Dark/System <.option_toggle>, the top bar's icon switch):
 * each button's own `phx-click`/`phx-value-option` round-trips to the server
 * to save the choice, this hook only does the instant class flip.
 */
export const AppearanceToggle = {
  mounted() {
    this.el.addEventListener("click", (event) => {
      const button = event.target.closest("button[phx-value-option]");
      if (!button) return;

      applyAppearance(button.getAttribute("phx-value-option"));
    });
  }
};

function applyAppearance(preference) {
  const root = document.documentElement;

  if (preference === "dark") {
    root.classList.add("dark");
  } else if (preference === "light") {
    root.classList.remove("dark");
  } else {
    // "system" — no stored preference; follow the OS setting directly.
    let prefersDark = false;
    try {
      prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
    } catch (e) {
      // matchMedia unsupported; fall back to light.
    }
    root.classList.toggle("dark", prefersDark);
  }
}
