#!/usr/bin/env python3
"""The dashboard bundle must still be what the two real files say.

    python3 scripts/check_send_sms_bundle_is_current.py

`supabase/functions/send-sms/bundled_for_dashboard.ts` is generated from
`index.ts` and `hook.ts` so that an operator whose CLI cannot deploy has one
file to paste. A generated copy that drifts from its source is worse than no
copy: it looks authoritative, it is pasted into a live project, and the fault
it carries was fixed weeks ago in the file everybody reads.

This regenerates it in memory and fails on any difference — the same way the
apply-all paste is held to `supabase/migrations/` and the brand assets to the
master logo.

If the bundle is deleted deliberately, this passes. It exists for a situation
that should not be permanent: the CLI returning 403 on `functions deploy`.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'scripts'))

BUNDLE = REPO / 'supabase' / 'functions' / 'send-sms' / 'bundled_for_dashboard.ts'

if not BUNDLE.is_file():
    print('OK: no dashboard bundle, so nothing can drift from its source.')
    raise SystemExit(0)

from build_send_sms_bundle import build  # noqa: E402

want = build()
have = BUNDLE.read_text()

if want != have:
    print('The dashboard bundle is stale:\n')
    print(f'  * {BUNDLE.relative_to(REPO)} is not what index.ts and hook.ts '
          'now say. It is generated, and somebody edited one of its sources '
          '(or the bundle itself).\n')
    print('  * Regenerate it:  python3 scripts/build_send_sms_bundle.py\n')
    want_lines, have_lines = want.splitlines(), have.splitlines()
    print(f'  * {len(have_lines)} lines on disk against {len(want_lines)} '
          'regenerated\n')
    sys.exit(1)

# The build marker, which is what lets --check tell a current deployment from
# a stale one. A bundle regenerated without re-stamping carries the previous
# build's fingerprint, so the probe would call a fresh paste stale, or worse,
# call a stale one fresh.
from stamp_send_sms_version import current, fingerprint  # noqa: E402

stamped, implied = current(), fingerprint()
if stamped != implied:
    print('The build marker is stale:\n')
    print(f'  * SOURCE_FINGERPRINT says {stamped!r}, the sources hash to '
          f'{implied!r}.\n')
    print('  * Re-stamp and regenerate:\n'
          '      python3 scripts/stamp_send_sms_version.py\n'
          '      python3 scripts/build_send_sms_bundle.py\n')
    print('  * Until then `wire_up_sms_provider.sh --check` compares the live '
          'deployment\n    against the wrong value and its verdict means '
          'nothing.')
    sys.exit(1)

print('OK: the dashboard bundle is exactly what index.ts and hook.ts say.')
print(f'  * {len(have.splitlines())} lines, regenerated and compared')
print(f'  * build marker {implied}, which --check compares the live function '
      f'against')
