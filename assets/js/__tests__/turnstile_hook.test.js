/**
 * Tests for the Cloudflare Turnstile Phoenix LiveView hook.
 *
 * Focus: the widget renders and its token reaches the hidden field. The hook
 * injects api.js from JS, so the script is always async — and Cloudflare's
 * turnstile.ready() throws for an async script, which used to leave the form
 * submitting an empty token.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { TurnstileHook } from '../hooks/turnstile_hook';

function makeForm() {
  const form = document.createElement('form');
  form.dataset.siteKey = 'test-site-key';
  form.dataset.recaptchaAction = 'booking_form';
  form.dataset.recaptchaParamRoot = 'booking';

  const hidden = document.createElement('input');
  hidden.type = 'hidden';
  hidden.name = 'booking[cf-turnstile-response]';
  form.appendChild(hidden);

  const container = document.createElement('div');
  container.id = 'booking-cf-turnstile';
  form.appendChild(container);

  document.body.appendChild(form);
  return { form, hidden, container };
}

function mountHook(form) {
  const hook = Object.create(TurnstileHook);
  hook.el = form;
  hook.mounted();
  return hook;
}

// Mirrors Cloudflare's api.js: render() hands the token to the callback, and
// ready() refuses to run when the script was loaded async/defer.
function turnstileStub() {
  return {
    ready: vi.fn(() => {
      throw new Error(
        '[Cloudflare Turnstile] Remove async/defer from the Turnstile api.js script tag before using turnstile.ready().'
      );
    }),
    render: vi.fn((_container, options) => {
      options.callback('token-from-cloudflare');
      return 'widget-1';
    }),
    reset: vi.fn(),
    remove: vi.fn(),
  };
}

describe('TurnstileHook', () => {
  beforeEach(() => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
  });

  afterEach(() => {
    document.head.innerHTML = '';
    document.body.innerHTML = '';
    delete window.turnstile;
    vi.restoreAllMocks();
  });

  test('renders the widget into its container once api.js has loaded', () => {
    const { form, hidden, container } = makeForm();
    mountHook(form);

    const script = document.head.querySelector('script[src*="challenges.cloudflare.com"]');
    expect(script).not.toBeNull();

    window.turnstile = turnstileStub();
    script.onload();

    expect(window.turnstile.ready).not.toHaveBeenCalled();
    expect(window.turnstile.render).toHaveBeenCalledWith(
      container,
      expect.objectContaining({ sitekey: 'test-site-key', action: 'booking_form' })
    );
    expect(hidden.value).toBe('token-from-cloudflare');
  });

  test('renders straight away when api.js is already on the page', () => {
    window.turnstile = turnstileStub();

    const { form, hidden } = makeForm();
    mountHook(form);

    expect(window.turnstile.ready).not.toHaveBeenCalled();
    expect(window.turnstile.render).toHaveBeenCalledTimes(1);
    expect(hidden.value).toBe('token-from-cloudflare');
  });
});
