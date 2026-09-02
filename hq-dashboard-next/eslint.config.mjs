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
  {
    // ── The shrinking allowlist ───────────────────────────────────────────────
    // Eight pre-existing `set-state-in-effect` sites, all the same shape: an
    // effect that calls an async fetch which then sets state. Fixing them means
    // restructuring data loading in components with NO test coverage, on a
    // console that dispatches responders to emergencies. That is a real change
    // with real risk, and it does not belong in a lint sweep — the failure mode
    // (a dashboard that silently stops refreshing) is exactly the class of
    // defect this audit keeps finding.
    //
    // Fix them behind tests, then delete the file from this list. When the list
    // is empty, delete the block.
    files: [
      "src/app/dashboard/page.tsx",
      "src/components/AdminDirectory.tsx",
      "src/components/AgencyAccessManager.tsx",
      "src/components/AgencyPortal.tsx",
      "src/components/LiveMap.tsx",
      "src/components/UninstallRequests.tsx",
    ],
    rules: {
      "react-hooks/set-state-in-effect": "warn",
    },
  },
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
