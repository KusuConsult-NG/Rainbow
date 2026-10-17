#!/usr/bin/env python3
"""Every failure send-sms can return must reach the citizen as "report this".

    python3 scripts/check_every_hook_failure_is_explained.py

## What went wrong

`AuthService.describeOtpSendFailure` sorts a send failure into one of two
useful things to say: *this is yours to retry*, or *this is ours, report it*.
Its branch for the hook's own failures matched three substrings — `hook`,
`termii`, `not configured` — and `test/otp_send_failure_message_test.dart`
asserted five wordings against it.

All five were taken FROM THAT BRANCH rather than from the function, so the test
could only ever confirm what was already matched. `supabase/functions/send-sms`
can return **fourteen** distinct reasons. Five of them matched nothing and fell
through to:

    THE CODE COULD NOT BE SENT. TRY AGAIN.

which is the lever-not-connected-to-anything message that whole method was
written to avoid, said to somebody who may be reporting a kidnapping.

**The worst of the five was `no v1 signature matched`** — what a signing-secret
MISMATCH produces, the dashboard holding one value and `SEND_SMS_HOOK_SECRET`
another. It fails every sign-in, forever, and it is the likeliest
misconfiguration left once everything else is wired, because
`wire_up_sms_provider.sh --check` cannot see it: its POST probe proves the
secret is SET and rejects a BAD signature, and a mismatched secret does exactly
that. Every probe green, nobody can sign in, and the app says "try again".

## What this checks

It reads the reasons out of the Deno function — `hookError(...)`,
`notSent(...)` and `reason:` literals — and, for each, requires that one of the
substrings the Dart misconfiguration branch actually matches on is present in
it. The list of substrings is read out of `auth_service.dart` too, so neither
side can be edited into disagreeing with the other.

This is a cross-language check, which is why no test caught it: 767 Flutter
tests never read TypeScript, and the 25 Deno tests for the hook never read
Dart. The contract between them lived in nobody's file.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FUNCTION = REPO / 'supabase' / 'functions' / 'send-sms'
DART = REPO / 'lib' / 'services' / 'auth_service.dart'

# The one reason a real hook call can never produce: it is the answer to a GET,
# and Auth only ever POSTs. `--check` relies on it as the healthy GET verdict.
# Named here rather than filtered by accident, so that adding a second
# exception is a deliberate act somebody has to write down.
NOT_FROM_A_REAL_CALL = {'send-sms accepts post'}


def live(path: Path) -> str:
    """The file with // comments and /* */ blocks removed."""
    src = re.sub(r'/\*.*?\*/', '', path.read_text(), flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n'))


# ── the reasons the function can return ─────────────────────────────────────
reasons: dict[str, str] = {}          # lowercased reason -> where it is
if not FUNCTION.is_dir():
    print(f'FAIL: {FUNCTION.relative_to(REPO)} is not there, so this check '
          f'cannot read the reasons it is supposed to pin.')
    sys.exit(1)

PATTERNS = (
    # hookError(503, 'hook is not configured')
    re.compile(r"hookError\(\s*\d+\s*,\s*(['\"`])(?P<msg>[^'\"`]*)\1"),
    # notSent('Termii refused the message', data)
    re.compile(r"notSent\(\s*(['\"`])(?P<msg>[^'\"`]*)\1"),
    # { ok: false, status: 401, reason: 'no v1 signature matched' }
    re.compile(r"reason:\s*(['\"`])(?P<msg>[^'\"`]*)\1"),
)

for source in sorted(FUNCTION.glob('*.ts')):
    # bundled_for_dashboard.ts is generated FROM the other two and is already
    # held to them by check_send_sms_bundle_is_current.py. Reading it here
    # would double every reason and say nothing new.
    if source.name == 'bundled_for_dashboard.ts':
        continue
    code = live(source)
    for pattern in PATTERNS:
        for match in pattern.finditer(code):
            # A template literal keeps only its literal prefix:
            # `could not reach Termii: ${err…}` varies per failure, and the
            # part that identifies it does not.
            text = match.group('msg').split('${')[0].strip()
            if text and not text.startswith('...'):
                reasons.setdefault(
                    text.lower(), f'{source.relative_to(REPO)}')

if not reasons:
    print('FAIL: no failure reasons found in '
          f'{FUNCTION.relative_to(REPO)} — either the function stopped '
          'reporting why it refused, or this check can no longer read it. '
          'Either way it is not proving anything.')
    sys.exit(1)

# ── the substrings the Dart branch actually matches on ──────────────────────
dart = live(DART)
branch = re.search(
    r'if \(([^{]*?)\)\s*\{\s*return\s+\'SMS SIGN-IN IS MISCONFIGURED',
    dart, re.S)
if branch is None:
    print('FAIL: could not find the misconfiguration branch in '
          f'{DART.relative_to(REPO)}. If the message was reworded, update '
          'this check; if the branch was deleted, every hook failure now '
          'tells the citizen to try again.')
    sys.exit(1)

matched = [m.group(1).lower() for m in
           re.finditer(r"text\.contains\('([^']*)'\)", branch.group(1))]
if not matched:
    print('FAIL: the misconfiguration branch matches on nothing.')
    sys.exit(1)

# ── every reason must be caught by one of them ──────────────────────────────
unexplained = []
for reason, where in sorted(reasons.items()):
    if reason in NOT_FROM_A_REAL_CALL:
        continue
    if not any(needle in reason for needle in matched):
        unexplained.append(f'{where}: "{reason}"')

if unexplained:
    print('FAIL: send-sms can refuse for reasons the app calls "try again".\n')
    for item in unexplained:
        print(f'  - {item}')
    print(f'\n  The branch matches on: {", ".join(repr(m) for m in matched)}')
    print('\n  Each of these reaches the citizen as "THE CODE COULD NOT BE '
          'SENT. TRY AGAIN." —\n  a permanent deployment fault described as '
          'something retrying will fix.\n  Add a substring to the '
          'misconfiguration branch in lib/services/auth_service.dart.')
    sys.exit(1)

checked = len(reasons) - len(NOT_FROM_A_REAL_CALL & set(reasons))
print('OK: every way send-sms can refuse is reported as ours, not theirs.')
print(f'  * {checked} failure reasons read from '
      f'{FUNCTION.relative_to(REPO)}/*.ts')
print(f'  * each matched by one of: {", ".join(repr(m) for m in matched)}')
for excluded in sorted(NOT_FROM_A_REAL_CALL & set(reasons)):
    print(f'  ~ not required — "{excluded}" answers a GET, and Auth only POSTs')
