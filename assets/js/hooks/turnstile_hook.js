/**
 * Phoenix LiveView hook for Cloudflare Turnstile integration
 *
 * Renders a Turnstile widget into the container the server placed inside the
 * form and keeps its token in the hidden field the server expects. Unlike
 * reCAPTCHA v3's on-demand `execute()`, Turnstile solves in the background
 * (or asks for a click) according to whichever widget mode the sitekey was
 * configured with on Cloudflare's dashboard — this hook deliberately does not
 * override that with an `appearance`/`size` param.
 */
export const TurnstileHook = {
  mounted() {
    this.siteKey = this.el.dataset.siteKey;
    this.turnstileAction = this.el.dataset.recaptchaAction || 'contact_form';
    this.paramRoot = this.el.dataset.recaptchaParamRoot || 'contact';
    this.containerEl = this.el.querySelector('[id$="-cf-turnstile"]');
    this.currentToken = null;
    this.usedToken = null;
    this.widgetId = null;
    this.handleSubmit = () => this.refreshOnRetry();
    this.el.addEventListener('submit', this.handleSubmit);
    this.loadTurnstile();
  },

  updated() {
    // Restore the token after LiveView re-renders the form (which resets the hidden field to "")
    if (this.currentToken) {
      this.setHiddenField(this.currentToken);
    }
  },

  destroyed() {
    if (this.handleSubmit) {
      this.el.removeEventListener('submit', this.handleSubmit);
    }

    if (window.turnstile && this.widgetId !== null) {
      window.turnstile.remove(this.widgetId);
    }
  },

  loadTurnstile() {
    if (!this.siteKey || !this.containerEl) {
      console.warn('Turnstile site key or container missing; skipping Turnstile hook setup');
      return;
    }

    if (window.turnstile) {
      window.turnstile.ready(() => this.renderWidget());
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js';
    script.async = true;
    script.defer = true;

    // Propagate the page's CSP nonce so the widget's own injected scripts
    // aren't blocked once script-src drops 'unsafe-inline'.
    const nonce = document.querySelector('meta[name="csp-nonce"]')?.content;
    if (nonce) {
      script.nonce = nonce;
      script.setAttribute('nonce', nonce);
    }

    let scriptLoaded = false;

    script.onload = () => {
      scriptLoaded = true;
      window.turnstile.ready(() => this.renderWidget());
    };
    script.onerror = () => this.handleTurnstileLoadError();
    script.onabort = () => this.handleTurnstileLoadError();

    document.head.appendChild(script);

    // Fallback: if script hasn't loaded in 10 seconds, treat it as failure
    setTimeout(() => {
      if (!scriptLoaded && !window.turnstile) {
        console.warn('Turnstile script did not load within 10 seconds; treating as blocked');
        this.handleTurnstileLoadError();
      }
    }, 10000);
  },

  renderWidget() {
    if (!window.turnstile || this.widgetId !== null) return;

    this.widgetId = window.turnstile.render(this.containerEl, {
      sitekey: this.siteKey,
      action: this.turnstileAction,
      callback: (token) => {
        this.currentToken = token;
        this.setHiddenField(token);
      },
      'error-callback': () => this.handleTurnstileLoadError(),
      'expired-callback': () => {
        this.currentToken = null;
        if (window.turnstile && this.widgetId !== null) {
          window.turnstile.reset(this.widgetId);
        }
      }
    });
  },

  handleTurnstileLoadError() {
    console.error('Failed to load Turnstile widget (blocked by CSP, network, or extension).');
    // Set a special marker so the server can distinguish script-blocked from a missing token
    this.currentToken = 'TURNSTILE_SCRIPT_BLOCKED';
    this.setHiddenField(this.currentToken);
  },

  // Each Turnstile token is single-use. If the widget already handed a token
  // to a previous submit attempt (validation error, transient failure), ask
  // it to re-execute so a retry doesn't hit Cloudflare's
  // "timeout-or-duplicate" rejection. Best-effort: for an interactive widget
  // this may require the visitor to solve it again.
  refreshOnRetry() {
    if (this.usedToken !== this.currentToken) {
      this.usedToken = this.currentToken;
      return;
    }

    this.usedToken = this.currentToken;
    if (window.turnstile && this.widgetId !== null) {
      window.turnstile.reset(this.widgetId);
    }
  },

  setHiddenField(value) {
    const form = this.el;
    const hiddenField =
      form.querySelector(`input[name="${this.paramRoot}[cf-turnstile-response]"]`) ||
      form.querySelector('#cf-turnstile-response');

    if (hiddenField) {
      hiddenField.value = value;
    }
  }
};
