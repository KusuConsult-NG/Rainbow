#!/usr/bin/env node
'use strict';
/**
 * Turn a minified Flutter-web stack frame back into Dart file:line.
 *
 *   node scripts/local_e2e/resolve_dart_frames.js <build-dir> <line:col> [line:col ...]
 *   node scripts/local_e2e/resolve_dart_frames.js build/web-profile 41086:3 40942:27
 *
 * ## Why this exists
 *
 * Typing into the staff password field makes the Flutter web engine throw
 * `Cannot read properties of null (reading 'toString')` — twice, while the
 * sign-in itself still succeeds. Six plausible causes were tested with a build
 * and a probe each and every one was wrong, so guessing has been exhausted; the
 * remaining route is to read the stack.
 *
 * A `--release` build cannot be read: it ships minified with no source map, and
 * the top frame is literally `q.toString`. A build made with `--source-maps`
 * emits `main.dart.js.map`, and that is what this resolves against.
 *
 * It is a script rather than a one-off command because the mapping has to be
 * done the same way twice — once to find the frame, once to check a fix against
 * it — and because `main.dart.js.map` for this app is tens of megabytes, which
 * is not something to hand-search.
 *
 * ## Reading the output
 *
 * Frames inside `packages/flutter/src/...` or `dart-sdk/` are engine or
 * framework code; frames inside `lib/` are this application. The question this
 * is meant to answer is which of those the null originates in — because an
 * engine frame with no `lib/` frame beneath it means the defect is not in code
 * this repository controls, and the honest response is to report it upstream
 * rather than keep changing the login screen in the hope it goes away.
 */

const fs = require('fs');
const path = require('path');

async function main() {
  const [dir, ...frames] = process.argv.slice(2);
  if (!dir || !frames.length) {
    console.error('usage: resolve_dart_frames.js <build-dir> <line:col> [line:col ...]');
    console.error('  e.g. resolve_dart_frames.js build/web-profile 41086:3');
    return 2;
  }
  const mapPath = path.join(dir, 'main.dart.js.map');
  if (!fs.existsSync(mapPath)) {
    console.error(`✗ ${mapPath} does not exist.`);
    console.error('  Build with source maps first:');
    console.error('    flutter build web --profile --source-maps \\');
    console.error(`      --output ${dir} --no-web-resources-cdn \\`);
    console.error('      --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \\');
    console.error('      --dart-define=SUPABASE_ANON_KEY=local-e2e-anon-key-not-a-real-credential');
    return 2;
  }

  // The parser lives in the console's node_modules; this script has no
  // package.json of its own and adding one for a diagnostic is not worth it.
  const smPath = path.join(__dirname, '..', '..', 'hq-dashboard-next',
                           'node_modules', 'source-map');
  let SourceMapConsumer;
  try {
    ({ SourceMapConsumer } = require(smPath));
  } catch (err) {
    console.error(`✗ could not load the source-map parser from ${smPath}`);
    console.error(`  ${err.message}`);
    console.error('  Run `npm ci` in hq-dashboard-next/ first.');
    return 2;
  }

  const bytes = fs.statSync(mapPath).size;
  console.log(`map: ${mapPath} (${(bytes / 1e6).toFixed(1)} MB)\n`);
  const consumer = await new SourceMapConsumer(
    JSON.parse(fs.readFileSync(mapPath, 'utf8')));

  try {
    for (const frame of frames) {
      const [l, c] = frame.split(':').map(Number);
      if (!Number.isFinite(l)) {
        console.log(`${frame}  → not a line:col`);
        continue;
      }
      // Flutter's dart2js output is one enormous line per function in places,
      // so an exact match often misses; LEAST_UPPER_BOUND then nearest is what
      // actually resolves these.
      let pos = consumer.originalPositionFor({
        line: l, column: Number.isFinite(c) ? c : 0,
        bias: SourceMapConsumer.GREATEST_LOWER_BOUND,
      });
      if (!pos || pos.source == null) {
        pos = consumer.originalPositionFor({
          line: l, column: Number.isFinite(c) ? c : 0,
          bias: SourceMapConsumer.LEAST_UPPER_BOUND,
        });
      }
      if (!pos || pos.source == null) {
        console.log(`${frame}  → no mapping`);
        continue;
      }
      const where = /packages\/flutter\/|dart-sdk\/|packages\/flutter_web/.test(pos.source)
        ? 'FRAMEWORK/ENGINE'
        : (/\/lib\/|^lib\//.test(pos.source) ? 'THIS APP' : 'other package');
      console.log(`${frame}  → ${pos.source}:${pos.line}:${pos.column ?? 0}`
                  + `${pos.name ? `  (${pos.name})` : ''}   [${where}]`);
    }
  } finally {
    consumer.destroy();
  }
  return 0;
}

main().then((c) => process.exit(c)).catch((e) => {
  console.error(e); process.exit(1);
});
