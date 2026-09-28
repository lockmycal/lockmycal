/**
 * AppearanceToggle hook
 *
 * The <html> class is set server-side on first render (see root.html.heex +
 * AppAppearanceHook), but that layout is rendered once per HTTP request and
 * never re-patched by LiveView — a click on a toggle only updates the
 * component's own DOM, so without this hook the saved preference wouldn't
 * visibly apply until the next full page load.
 *
 * Two shapes of caller, distinguished by markup:
 *  - Mounted on a wrapper containing `button[phx-value-option]` children
 *    (Profile Settings' 3-way Light/Dark/System <.option_toggle>): the
 *    wrapper's own `phx-click`/`phx-value-option` already round-trips to the
 *    server, this hook only does the instant class flip.
 *  - Mounted directly on a single button carrying `data-appearance-flip`
 *    (the topbar sun/moon quick toggle): there's no separate "value" to read
 *    from the DOM, so the hook computes the opposite of the *currently
 *    visible* state (not the stored preference — under "System" the server
 *    never resolved a concrete value, only the client knows what's actually
 *    showing), flips the class, and pushes the result to the server itself.
 */
export const AppearanceToggle = {
  mounted() {
    if (this.el.hasAttribute("data-appearance-flip")) {
      this.el.addEventListener("click", () => {
        const isDark = document.documentElement.classList.contains("dark");
        const next = isDark ? "light" : "dark";
        applyAppearance(next);
        this.pushEvent("change_appearance", { value: next });
      });
      return;
    }

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
