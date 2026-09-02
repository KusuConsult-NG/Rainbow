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
      // from adding more. They are now ERRORS everywhere, with a file-scoped
      // allowlist below for the sites that predate the gate.
      //
      // The allowlist can only shrink. New files, and new code in any file not
      // named there, fail the build.
      "react-hooks/set-state-in-effect": "error",
      "react-hooks/immutability": "error",

      // The premise of this rule is that next/image optimises the image. This
      // project sets `images: { unoptimized: true }` in next.config.ts, so that
      // optimisation is off and the rule's benefit largely does not apply.
      // Converting the four remaining <img> tags would also require inventing
      // explicit width/height for a logo and two avatars, which is a layout
      // change dressed up as a lint fix. Left visible, not silenced.
      "@next/next/no-img-element": "warn",
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
