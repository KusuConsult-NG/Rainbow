#!/usr/bin/env python3
"""The mobile sign-in flow must exist in exactly one place.

    python3 scripts/check_one_mobile_login.py

## What went wrong

The login screen grew a second step: a staff badge no longer signs anybody in
on its own, because the access code was never a secret — it was the email
local-part, a USERNAME — and the one password every officer shared was readable
in the APK (T-20). `AUTHORIZE ACCESS` now only reveals a password field and its
own label becomes `SIGN IN`.

Six harnesses under scripts/local_e2e/ carried their own copy of "type the
identifier, tap AUTHORIZE ACCESS, read the hash". Five of them typed a staff
badge. None was updated.

How that surfaced is the reason this check exists:

  * `tier_controls.js` returned the login screen's hash as though it had signed
    in, carried on, and died sixty seconds later inside an unrelated
    `waitForFunction(... canvas ...)` — the CI log pointed at a line that had
    nothing to do with the cause;
  * `chat_thread.js` signs in as `unit` and `hq`, never got past the login
    screen, and still reported **PASS**. A harness that passes without signing
    in is testing nothing, and nothing would ever have told us.

So the flow lives in `scripts/local_e2e/mobile_login.js`, it asserts each step,
and this check fails if a harness grows its own copy again.

## What counts as a copy

Typing `<role>@<DOMAIN>` — the staff badge — anywhere outside `mobile_login.js`.
The citizen phone/OTP path is matched too, since it drifts the same way.

A harness may still tap `authorize access` for its own reasons (pressing every
control on the login screen is a legitimate test), so the trigger is the
IDENTIFIER being typed, not the button being tapped. That is the part that only
makes sense as a sign-in.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
E2E = REPO / 'scripts' / 'local_e2e'
OWNER = 'mobile_login.js'

# Typing the staff badge, in any of the shapes the harnesses use.
#
# `typeText` and the optional leading `page,` are here because the typing
# MECHANISM changed and this signature was written around the call: the flow moved
# from `page.keyboard.type(...)` to a helper that sends Input.insertText, because
# puppeteer synthesises `-` as a keyup with location 1 and Flutter's web keyboard
# engine null-asserts on it. The claim this check makes is "the sign-in flow lives
# in one file", so it has to recognise the flow however the text gets typed —
# otherwise a legitimate change to the mechanism reads as the flow having been
# deleted, which is what happened.
STAFF_BADGE = re.compile(
    r"""(?:typeInto|typeText|type)\s*\(\s*(?:page\s*,\s*)?`\$\{[A-Za-z_]\w*\}@\$\{DOMAIN\}`""")
STAFF_BADGE_LITERAL = re.compile(
    r"""(?:typeInto|typeText|type)\s*\(\s*(?:page\s*,\s*)?`[a-z_]+@\$\{DOMAIN\}`""")
# The citizen path: the fixture phone, stripped of its country code.
CITIZEN_PHONE = re.compile(r"""byKey\(\s*['"]citizen['"]\s*\)\.phone\.replace""")

PATTERNS = (
    ('a staff badge is typed', STAFF_BADGE),
    ('a staff badge is typed', STAFF_BADGE_LITERAL),
    ('the citizen phone sign-in is typed', CITIZEN_PHONE),
)


def main() -> int:
    if not E2E.is_dir():
        print(f'✗ {E2E.relative_to(REPO)} is missing', file=sys.stderr)
        return 2
    owner = E2E / OWNER
    if not owner.exists():
        print(f'✗ {OWNER} does not exist — the shared sign-in flow is gone, so '
              f'this check cannot mean anything.', file=sys.stderr)
        return 2

    # The owner has to actually contain the flow, or this check passes by
    # pointing at an empty file.
    owner_text = owner.read_text(encoding='utf-8')
    if not any(p.search(owner_text) for _, p in PATTERNS):
        print(f'✗ {OWNER} no longer contains a sign-in flow. Either it moved — '
              f'in which case update OWNER here — or it was deleted.',
              file=sys.stderr)
        return 2

    problems: list[str] = []
    skipped: list[str] = []
    for path in sorted(E2E.glob('*.js')):
        if path.name == OWNER:
            continue
        text = path.read_text(encoding='utf-8')
        # Only the harnesses that drive the FLUTTER app. capture.js and
        # interact.js drive the Next.js console, whose login is a different
        # screen with real <input> elements and a <form> — signInMobile would be
        # the wrong flow there, and the first version of this check flagged them
        # anyway because it matched on `@${DOMAIN}` alone.
        if not re.search(r'flt-semantics|flutter-view|flt-glass-pane', text):
            if any(pat.search(text) for _, pat in PATTERNS):
                skipped.append(f'{path.name} (drives the console, not the app)')
            continue
        for label, pattern in PATTERNS:
            for m in pattern.finditer(text):
                line = text[:m.start()].count('\n') + 1
                problems.append(
                    f'{path.name}:{line}: {label} here. Call '
                    f'signInMobile(page, role) from {OWNER} instead — it does '
                    f'the password step and asserts that each one happened.')

    if problems:
        for p in problems:
            print(f'✗ {p}', file=sys.stderr)
        print(f'\n{len(problems)} copy/copies of the sign-in flow outside '
              f'{OWNER}.', file=sys.stderr)
        return 1

    users = sorted(p.name for p in E2E.glob('*.js')
                   if p.name != OWNER and 'signInMobile' in p.read_text(encoding='utf-8'))
    print(f'✓ the mobile sign-in flow lives only in {OWNER}; '
          f'{len(users)} harness(es) call it: {", ".join(users)}')
    for sk in skipped:
        print(f'  not checked: {sk}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
