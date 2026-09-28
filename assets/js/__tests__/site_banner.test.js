/**
 * Tests for the site banner dismiss handler (site_banner.js).
 *
 * Dismissal must hide the bar with an injected CSS rule rather than removing
 * the element — a LiveView-rendered banner would otherwise be re-added by the
 * next DOM patch — and must remember the banner's id per browser.
 */

import { describe, expect, test, beforeAll, beforeEach } from 'vitest';
import { installSiteBannerDismiss, SITE_BANNER_STORAGE_KEY } from '../site_banner';

function renderBanner(id) {
  document.body.innerHTML = `
    <div data-site-banner="${id}">
      <span>Hello</span>
      <button type="button" data-site-banner-dismiss="${id}">x</button>
    </div>`;
}

function hideRules() {
  return Array.from(document.head.querySelectorAll('style')).map((s) => s.textContent);
}

describe('installSiteBannerDismiss', () => {
  beforeAll(() => installSiteBannerDismiss());

  beforeEach(() => {
    document.head.innerHTML = '';
    window.localStorage.clear();
  });

  test('clicking dismiss remembers the id and injects a hide rule, keeping the element', () => {
    renderBanner('abc123');

    document.querySelector('[data-site-banner-dismiss]').click();

    expect(window.localStorage.getItem(SITE_BANNER_STORAGE_KEY)).toBe('abc123');
    expect(hideRules()).toEqual(['[data-site-banner="abc123"]{display:none!important}']);
    expect(document.querySelector('[data-site-banner]')).not.toBeNull();
  });

  test('clicks elsewhere do nothing', () => {
    renderBanner('abc123');

    document.querySelector('span').click();

    expect(window.localStorage.getItem(SITE_BANNER_STORAGE_KEY)).toBeNull();
    expect(hideRules()).toEqual([]);
  });

  test('an id that is not base64url is ignored rather than put in a selector', () => {
    renderBanner('placeholder');
    const hostile = 'x"]{}body{display:none';
    document.querySelector('[data-site-banner-dismiss]').setAttribute('data-site-banner-dismiss', hostile);

    document.querySelector('[data-site-banner-dismiss]').click();

    expect(window.localStorage.getItem(SITE_BANNER_STORAGE_KEY)).toBeNull();
    expect(hideRules()).toEqual([]);
  });
});
