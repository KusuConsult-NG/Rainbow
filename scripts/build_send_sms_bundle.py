#!/usr/bin/env python3
"""One file to paste into the dashboard, built from the two real ones.

    python3 scripts/build_send_sms_bundle.py

## Why this exists

`send-sms` is two files: `index.ts`, the Deno server, and `hook.ts`, the logic
it imports — split so the logic can be tested without deploying, which is how
two faults that stopped every citizen signing in were found.

The CLI handles two files without being asked. The dashboard's function editor
is where an operator ends up when the CLI will not deploy — and ours would not:

    unexpected deploy status 403: Your account does not have the necessary
    privileges to access this endpoint.

An operator in that position pastes a file. They pasted `index.ts` and the
function could not boot, because `./hook.ts` was not beside it. Then they
pasted `hook.ts` as the function, and it has no `serve()` at all — it is a
library. Neither file is the thing to paste, and nothing said so.

So this makes the thing to paste: one file, generated from both, with the
import line removed because the names are then in the same module.

`hook.ts` imports nothing, which is what makes inlining safe. The generator
asserts that rather than assuming it — an import added there later would be
silently dropped, and the bundle would fail at runtime in a dashboard with no
good way to debug it.

## This is generated, and a copy that drifts is worse than no copy

`scripts/check_send_sms_bundle_is_current.py` regenerates and compares on every
push, the same way the apply-all paste and the brand assets are held to their
sources. Edit `index.ts` or `hook.ts`; never edit the bundle.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FUNCTION = REPO / 'supabase' / 'functions' / 'send-sms'
HOOK = FUNCTION / 'hook.ts'
INDEX = FUNCTION / 'index.ts'
BUNDLE = FUNCTION / 'bundled_for_dashboard.ts'

IMPORT_OF_HOOK = re.compile(
    r"^import\s*\{[^}]*\}\s*from\s*'\./hook\.ts';\s*$", re.M | re.S)

HEADER = """// GENERATED — DO NOT EDIT. Run scripts/build_send_sms_bundle.py.
//
// index.ts and hook.ts, in one file, for pasting into the Supabase dashboard's
// function editor when the CLI cannot deploy. Deploy with JWT verification
// OFF: the Auth hook fires before any JWT exists, so with it on the platform
// refuses every real call before this code runs — and logs nothing, which
// reads exactly like "the hook is not wired".
//
// Prefer the CLI, which needs no bundle:
//
//     supabase functions deploy send-sms --no-verify-jwt --project-ref <ref>
//
// Edit supabase/functions/send-sms/index.ts or hook.ts. Never edit this file:
// check_send_sms_bundle_is_current.py regenerates it and fails on a diff.

"""


def build() -> str:
    hook = HOOK.read_text()
    index = INDEX.read_text()

    stray = [line for line in hook.split('\n')
             if re.match(r'^\s*import\s', line)]
    if stray:
        raise SystemExit(
            'hook.ts has imports now:\n  ' + '\n  '.join(stray) + '\n'
            'Inlining it would drop them and the bundle would fail at runtime '
            'in a dashboard, which is the worst place to debug. Teach this '
            'generator to hoist them, or stop generating the bundle.')

    if not IMPORT_OF_HOOK.search(index):
        raise SystemExit(
            "index.ts no longer imports from './hook.ts' in the shape this "
            'generator removes. Check the import and update the pattern.')

    body = IMPORT_OF_HOOK.sub('', index)
    return (HEADER
            + '// ── hook.ts ' + '─' * 64 + '\n\n'
            + hook.rstrip() + '\n\n'
            + '// ── index.ts ' + '─' * 63 + '\n'
            + body.lstrip('\n'))


def main() -> int:
    text = build()

    # Structural checks, because there is no Deno here to type-check with and
    # a bundle that does not boot is worse than no bundle.
    if "from './hook.ts'" in text:
        print('the import of ./hook.ts survived; the bundle would not resolve.')
        return 1
    if 'serve(' not in text:
        print('no serve() in the bundle — it would answer nothing.')
        return 1
    imported = re.search(r'import\s*\{([^}]*)\}\s*from\s*\'\./hook\.ts\';',
                         INDEX.read_text(), re.S)
    missing = [name.strip().rstrip(',') for name in imported.group(1).split('\n')
               if name.strip().rstrip(',')]
    absent = [n for n in missing
              if not re.search(
                  rf'export (?:async )?(?:function|const|type) {re.escape(n)}\b', text)]
    if absent:
        print('the bundle does not define: ' + ', '.join(absent))
        return 1

    BUNDLE.write_text(text)
    print(f'{BUNDLE.relative_to(REPO)} written, {len(text.splitlines())} lines')
    print(f'  * every name index.ts imported is defined in it ({len(missing)})')
    print('  * no ./hook.ts import survives, and serve() is present')
    print('  * paste it as the function, with JWT verification OFF')
    return 0


if __name__ == '__main__':
    sys.exit(main())
