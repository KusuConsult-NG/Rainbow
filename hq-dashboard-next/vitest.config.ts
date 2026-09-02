import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

/**
 * Component tests for the console.
 *
 * The dashboard had NO unit test framework — only `verify-web-routes.js`, which
 * drives a browser and can tell you a page returned 200, not whether it stops
 * refreshing. That gap is why the `set-state-in-effect` allowlist could not be
 * cleared: the fix restructures data loading in components that dispatch
 * responders, and "it still compiles" is not evidence.
 */
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./vitest.setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
});
