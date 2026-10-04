/**
 * Tests for the Flash hook in utility_hooks.js.
 *
 * A flash sits outside any open modal, and a click that reaches LiveView's
 * window listener from there fires the modal's phx-click-away, closing the
 * dialog the flash is reporting on. So the flash never clicks itself to
 * auto-dismiss, and stops a click on it from bubbling, running its own
 * phx-click commands instead.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { Flash } from '../utility_hooks';

const DISMISS = '[["push",{"event":"lv:clear-flash","value":{"key":"error"}}]]';

function makeHook({ close } = {}) {
  const el = document.createElement('div');
  document.body.appendChild(el);
  el.setAttribute('phx-click', DISMISS);
  if (close !== undefined) el.dataset.close = close;
  const exec = vi.fn();
  const hook = Object.assign(Object.create(Flash), { el, js: () => ({ exec }) });
  return { hook, el, exec };
}

describe('Flash auto-dismiss', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  test('runs the phx-click commands after 6 seconds without clicking the flash', () => {
    const { hook, el, exec } = makeHook();
    const click = vi.spyOn(el, 'click');

    hook.mounted();
    vi.advanceTimersByTime(5999);
    expect(exec).not.toHaveBeenCalled();

    vi.advanceTimersByTime(1);
    expect(exec).toHaveBeenCalledWith(DISMISS);
    expect(click).not.toHaveBeenCalled();
  });

  test('stays when data-close is "false"', () => {
    const { hook, exec } = makeHook({ close: 'false' });

    hook.mounted();
    vi.advanceTimersByTime(6000);

    expect(exec).not.toHaveBeenCalled();
  });

  test('destroyed cancels the pending dismiss', () => {
    const { hook, exec } = makeHook();

    hook.mounted();
    hook.destroyed();
    vi.advanceTimersByTime(6000);

    expect(exec).not.toHaveBeenCalled();
  });
});

describe('Flash click', () => {
  test('dismisses the flash without the click reaching the window', () => {
    const { hook, el, exec } = makeHook();
    const windowClick = vi.fn();
    window.addEventListener('click', windowClick);

    hook.mounted();
    el.click();

    expect(exec).toHaveBeenCalledWith(DISMISS);
    expect(windowClick).not.toHaveBeenCalled();

    hook.destroyed();
    window.removeEventListener('click', windowClick);
  });

  test('a click on a button inside the flash is handled the same way', () => {
    const { hook, el, exec } = makeHook();
    const button = document.createElement('button');
    el.appendChild(button);
    const windowClick = vi.fn();
    window.addEventListener('click', windowClick);

    hook.mounted();
    button.click();

    expect(exec).toHaveBeenCalledWith(DISMISS);
    expect(windowClick).not.toHaveBeenCalled();

    hook.destroyed();
    window.removeEventListener('click', windowClick);
  });

  test('destroyed stops handling clicks', () => {
    const { hook, el, exec } = makeHook();

    hook.mounted();
    hook.destroyed();
    el.click();

    expect(exec).not.toHaveBeenCalled();
  });
});
