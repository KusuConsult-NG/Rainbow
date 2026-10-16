/**
 * The Plateau Eye palette, for the places a CSS variable cannot reach.
 *
 * Most of the console takes its colours from `--token`s in `globals.css`. Two
 * kinds of value cannot: a Leaflet marker or polygon style, which is handed to
 * a library as a string, and a hex with an alpha suffix (`${colour}22`). Those
 * were written as literals — and they drifted.
 *
 * `incident-dossier.ts` returned the red `E3-1E-24` for CRITICAL with the
 * comment "AppColors.danger", and its test asserted the same value as "the
 * app's palette spelled out". `AppColors.danger` was `D3-2F-2F` and is now
 * `B3-26-1E`; it was never `E3-1E-24`, which is the red of the brand this
 * product was called before. (Written with dashes here on purpose: a sweep
 * that rewrites colour literals should not be able to rewrite the sentence
 * explaining why the sweep happened — which is exactly what it did the first
 * time.) Thirty-seven of those literals were scattered through the
 * console, along with Tailwind indigo, violet, amber, slate and sky — the map
 * drew Plateau State in a red that belongs to no current mark.
 *
 * So: one module. `scripts/check_brand_colours.py` re-samples
 * `Plateau_Eye_Logo.png` on every push and fails if this file, the Flutter
 * palette or `globals.css` disagrees with it or with each other.
 */

/** The three ink colours of the logo, and the ramp built from them. */
export const BRAND = {
  // ── The mark's own ink ───────────────────────────────────────────────
  /** Oxford Navy — the ring and the wordmark. */
  navy: '#0B234B',
  /** Highland Emerald — the Plateau State silhouette. */
  emerald: '#0F6C32',
  /** Warm Gold — the inner ring. */
  gold: '#B99123',

  // ── Built from them ──────────────────────────────────────────────────
  /** Deep navy, for surfaces and the dark end of a navy gradient. */
  navyDark: '#06142C',
  /** Mid navy. */
  navyLight: '#163B72',
  /** Emerald, darkened for text on a light fill. */
  emeraldDeep: '#0B5027',
  /** Emerald, lightened — the last rung of the responder progression. */
  emeraldLight: '#1E8244',

  // ── Status ───────────────────────────────────────────────────────────
  /** Emergency red. One red, deep enough to sit beside Oxford Navy. */
  danger: '#B3261E',
  /** The dark end of the emergency gradient. */
  dangerDeep: '#7A1710',
  /** Warning. The brand gold, darkened until text on white clears 4.5:1. */
  warning: '#7E6112',
  /** Resolved / all clear. */
  success: '#0F6C32',

  // ── Tints, each one a fill behind dark text ──────────────────────────
  dangerTint: '#FBE4E2',
  goldTint: '#F6ECD2',
  navyTint: '#E6EAF1',
  emeraldTint: '#DDEEE2',

  // ── Neutrals ─────────────────────────────────────────────────────────
  background: '#FAFAF7',
  surface: '#FFFFFF',
  /** The next surface up from white — AppColors.surfaceContainerLow. */
  surfaceContainerLow: '#F7F7F7',
  textPrimary: '#1A1A1A',
  textSecondary: '#616161',
  textDim: '#757575',
  outline: '#E0E0E0',
  /** Body text on a navy surface. */
  onNavy: '#E4EBF5',
  /** Secondary text on a navy surface. */
  onNavyMuted: '#AFC0D8',
} as const;

export type BrandColour = (typeof BRAND)[keyof typeof BRAND];
