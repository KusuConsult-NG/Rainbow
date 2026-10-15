'use client';
import { useEffect } from 'react';

/**
 * Escape closes the thing that is on top.
 *
 * ## Why this exists
 *
 * The console had no `keydown` handler anywhere. The incident dossier — the
 * surface an operator works an emergency from — is a fixed overlay over the
 * whole screen, dismissed by clicking its backdrop or its close button, and
 * the mobile drawer is the same shape. Both opened with no way out but the
 * mouse.
 *
 * That is not a nicety on this console. The dossier covers the live feed and
 * the map; an operator who opened it on a report they did not mean to open has
 * to find a target with a pointer before they can see the board again. Escape
 * is what everybody already presses.
 *
 * ## What it does NOT do
 *
 * It does not trap focus, and it does not move focus into the overlay. Those
 * are the other half of a modal dialog and they need the dossier's own markup
 * to change (it is assembled inline in a 4,000-line component). This closes
 * the gap that costs an operator time today; focus management is named in
 * E2E_AUDIT_REPORT.md rather than half-done here.
 *
 * ## `enabled`, and who decides precedence
 *
 * It is safe to call this unconditionally from a component that renders
 * whether or not its overlay is open — but `enabled` does more than that. Two
 * listeners on `window` fire in REGISTRATION order, so the overlay that
 * mounted first sees the keystroke first, and no amount of
 * `stopPropagation` inside a handler can reorder that. Layering is therefore
 * the caller's to express: an overlay that sits under another passes
 * `enabled: open && !thingAboveIsOpen`, and Escape then closes exactly the
 * top one.
 */
export function useEscapeKey(enabled: boolean, onEscape: () => void): void {
  useEffect(() => {
    if (!enabled) return;
    const onKeyDown = (event: KeyboardEvent) => {
      // `event.key`, not `keyCode`: the latter is deprecated and reports 27
      // for Escape on some layouts and 0 on others.
      if (event.key !== 'Escape') return;
      onEscape();
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [enabled, onEscape]);
}
