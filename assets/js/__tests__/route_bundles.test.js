/**
 * Smoke tests for the route-specific JS bundle entry points
 * (assets/js/bundles/{auth,dashboard,public}.js).
 *
 * Regression coverage for the class of bug this project actually shipped:
 * a route bundle referencing a hook via `lazyHook(...)` without importing
 * `lazyHook` from `../dynamic_hooks`. That mistake throws a ReferenceError
 * while the bundle's top-level Hooks object literal is being built —
 * synchronously, *before* `initializeBundle()` is even called — so
 * `window.liveSocket.connect()` never runs for that route and the whole
 * page silently loses all LiveView interactivity (every phx-click/
 * phx-submit/phx-change, not just the one broken hook), with no
 * user-visible error at all. `auth.js`'s dead `BackgroundMotionToggle` hook
 * (a leftover from the video-background-to-gradient refactor) did exactly
 * this and broke the signup/login pages.
 *
 * `mix compile`/credo/dialyzer can't catch this — it's a plain browser
 * ReferenceError, only surfaced by actually evaluating the bundle. These
 * tests import each route bundle in jsdom and assert the module evaluates
 * cleanly (a bad top-level reference makes the dynamic import() reject).
 */

import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

// initializeBundle() (bundle_utils.js) only calls window.liveSocket.connect()
// once it finds window.liveSocket/window.CoreHooks already present.
// Pre-seeding them here lets each bundle resolve on its first check instead
// of retrying every 100ms for up to 10s of real time.
beforeEach(() => {
  window.liveSocket = { isConnected: () => true, connect: vi.fn(), hooks: {} };
  window.CoreHooks = {};
});

afterEach(() => {
  delete window.liveSocket;
  delete window.CoreHooks;
});

describe('route bundle entry points evaluate without throwing', () => {
  test('auth.js', async () => {
    await expect(import('../bundles/auth.js')).resolves.toBeDefined();
  });

  test('dashboard.js', async () => {
    await expect(import('../bundles/dashboard.js')).resolves.toBeDefined();
  });

  test('public.js', async () => {
    await expect(import('../bundles/public.js')).resolves.toBeDefined();
  });
});
