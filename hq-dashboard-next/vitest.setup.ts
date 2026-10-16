import '@testing-library/jest-dom/vitest';
import { cleanup } from '@testing-library/react';
import { afterEach, vi } from 'vitest';

// `src/lib/supabase.ts` calls assertPublicEnv() at module scope and builds a
// real browser client. Tests supply their own client per file; these keep the
// module import itself from throwing before that happens.
process.env.NEXT_PUBLIC_SUPABASE_URL ??= 'http://offline.invalid';
process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ??= 'test-anon-key';

// jsdom implements neither of these, and both are used by components under
// test: matchMedia by useMediaQuery, ResizeObserver by Leaflet.
if (!window.matchMedia) {
  window.matchMedia = ((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: () => {},
    removeEventListener: () => {},
    addListener: () => {},
    removeListener: () => {},
    dispatchEvent: () => false,
  })) as unknown as typeof window.matchMedia;
}

if (!globalThis.ResizeObserver) {
  globalThis.ResizeObserver = class {
    observe() {}
    unobserve() {}
    disconnect() {}
  } as unknown as typeof ResizeObserver;
}

// Node 22+ introduces an experimental globalThis.localStorage that throws or lacks
// jsdom methods when run without --localstorage-file. Provide an in-memory Storage implementation.
const createMemoryStorage = (): Storage => {
  let store: Record<string, string> = {};
  return {
    getItem: (key: string) => store[key] ?? null,
    setItem: (key: string, value: string) => { store[key] = String(value); },
    removeItem: (key: string) => { delete store[key]; },
    clear: () => { store = {}; },
    key: (index: number) => Object.keys(store)[index] ?? null,
    get length() { return Object.keys(store).length; },
  };
};

const memoryStorage = createMemoryStorage();
try {
  Object.defineProperty(window, 'localStorage', {
    value: memoryStorage,
    configurable: true,
    writable: true,
  });
} catch (_) {}

// jsdom performs no layout, so every element measures 0x0. Leaflet asks the
// container for its size to decide what is visible, concludes nothing is, and
// renders an empty marker pane — a map that looks initialised but shows no
// incidents. Giving elements a viewport-sized box makes the map behave, and is
// what lets LiveMap be tested at all.
const BOX = { width: 1024, height: 768 };
for (const [prop, value] of [
  ['clientWidth', BOX.width],
  ['clientHeight', BOX.height],
  ['offsetWidth', BOX.width],
  ['offsetHeight', BOX.height],
] as const) {
  Object.defineProperty(HTMLElement.prototype, prop, { configurable: true, value });
}
HTMLElement.prototype.getBoundingClientRect = function (): DOMRect {
  return {
    width: BOX.width, height: BOX.height,
    top: 0, left: 0, right: BOX.width, bottom: BOX.height, x: 0, y: 0,
    toJSON: () => ({}),
  } as DOMRect;
};

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});
