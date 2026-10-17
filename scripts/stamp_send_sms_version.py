#!/usr/bin/env python3
"""Stamp `SOURCE_FINGERPRINT` in send-sms with a hash of its own sources.

    python3 scripts/stamp_send_sms_version.py          # write it
    python3 scripts/stamp_send_sms_version.py --check   # verify only

Importable: `fingerprint()` returns the value the sources imply, which is what
`scripts/check_send_sms_bundle_is_current.py` and
`scripts/wire_up_sms_provider.sh` both compare against.

The hash covers `hook.ts` and `index.ts` with the fingerprint line itself
blanked — otherwise stamping a value would change the value.
"""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FUNCTION = REPO / 'supabase' / 'functions' / 'send-sms'
HOOK = FUNCTION / 'hook.ts'
INDEX = FUNCTION / 'index.ts'
LINE = re.compile(r"(export const SOURCE_FINGERPRINT = ')([0-9a-f]*)(';)")
PLACEHOLDER = "export const SOURCE_FINGERPRINT = '<stamped>';"


def fingerprint() -> str:
    """What the sources say this build is. 16 hex characters."""
    hook = LINE.sub(PLACEHOLDER, HOOK.read_text())
    digest = hashlib.sha256()
    digest.update(hook.encode())
    digest.update(INDEX.read_text().encode())
    return digest.hexdigest()[:16]


def current() -> str | None:
    found = LINE.search(HOOK.read_text())
    return found.group(2) if found else None


if __name__ == '__main__':
    want = fingerprint()
    have = current()
    if have is None:
        print(f'{HOOK.relative_to(REPO)} declares no SOURCE_FINGERPRINT.')
        sys.exit(1)
    if '--check' in sys.argv:
        if have != want:
            print(f'SOURCE_FINGERPRINT is {have!r}, the sources hash to '
                  f'{want!r}.\nRun: python3 {Path(__file__).relative_to(REPO)}')
            sys.exit(1)
        print(f'SOURCE_FINGERPRINT is current: {want}')
        sys.exit(0)
    HOOK.write_text(LINE.sub(rf"\g<1>{want}\g<3>", HOOK.read_text()))
    print(f'stamped SOURCE_FINGERPRINT = {want}')
