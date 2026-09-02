import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    rules: {
      "@typescript-eslint/no-explicit-any": "off",
      "@typescript-eslint/no-unused-vars": "off",
      "@next/next/no-sync-scripts": "off",
      "react-hooks/exhaustive-deps": "off",
      "@typescript-eslint/no-require-imports": "off",

      // ── RATCHET, tightened 2026-09-02 ──────────────────────────────────────
      // These were "warn" PROJECT-WIDE, which meant nothing stopped new code
      // from adding more. They are now ERRORS everywhere, with no exceptions —
      // the file-scoped allowlist this comment used to describe is gone, all
      // eight pre-existing sites having been fixed behind tests. See the note
      // below the rules block.
      "react-hooks/set-state-in-effect": "error",
      "react-hooks/immutability": "error",

      // ERROR, with four documented exceptions at their call sites.
      //
      // The rule's premise is that next/image optimises the image. This project
      // sets `images: { unoptimized: true }`, and the Next docs are explicit
      // that unoptimized means "served as-is from the src instead of changing
      // quality, size, or format" — so next/image would emit the same bytes.
      // For the three remote ones it would additionally require the Supabase
      // Storage host in `images.remotePatterns`: a second copy of the CSP's
      // img-src allowlist, in another file, to keep in sync.
      //
      // What IS real in the rule's concern is bandwidth, so that part is now
      // handled directly — every remote <img> carries loading="lazy" and
      // decoding="async". The login emblem stays eager on purpose: it is the
      // first thing on the sign-in page.
      //
      // `error` rather than `warn` because the four exceptions are argued at
      // their call sites. A NEW <img> should have to make that argument too,
      // not inherit a project-wide pass.
      "@next/next/no-img-element": "error",
    },
  },
  // ── The allowlist is GONE ─────────────────────────────────────────────────
  //
  // All eight `set-state-in-effect` sites across six files are fixed, so both
  // hooks rules above are now `error` project-wide with NO exceptions. Nothing
  // to maintain, and nothing for the next person to widen.
  //
  // Each fix went in behind characterisation tests written against the
  // ORIGINAL code first — see the *.test.tsx beside each component, added with
  // the vitest setup in this change. That order matters: the tests describe
  // behaviour that had to survive, not behaviour invented to match the result.
  //
  // The last one, LiveMap, was nearly left exempt on the grounds that Leaflet
  // needs real layout and so could not be unit tested. That turned out to be
  // wrong: Leaflet runs fine under jsdom once `matchMedia`, `ResizeObserver`
  // and element dimensions are stubbed (vitest.setup.ts). Without those stubs
  // the map initialises but its marker pane stays empty — which is precisely
  // the failure mode the tests now guard.
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
]);

export default eslintConfig;
