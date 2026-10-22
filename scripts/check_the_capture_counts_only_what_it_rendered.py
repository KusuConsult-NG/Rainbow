#!/usr/bin/env python3
"""A route that renders a fallback must not be counted as the screen it names.

    python3 scripts/check_the_capture_counts_only_what_it_rendered.py

## What went wrong

`mobile_capture.js` walks every route in `AppRoutes` by URL and ends with:

    every one of the app's 24 screens was rendered by at least one role

Six of those routes need `state.extra` — an alert, a category — and their
`pageBuilder` correctly falls back to another screen when it is null, because a
URL cannot carry an incident:

    /mission-intel       -> AgentDashboardScreen
    /mission-resolution  -> AgentDashboardScreen
    /secure-chat         -> AgentDashboardScreen
    /dispatcher-chat     -> HomeScreen
    /report-subtype      -> ReportCategoryScreen
    /report-details      -> ReportCategoryScreen

The walk sets the hash and then asks whether the hash is the route it wanted.
It is — the router renders the fallback WITHOUT redirecting the URL. So
`here === route` held, the route was recorded as covered, and a claim about a
quarter of the app's screens was false while reading green.

Found by probing why the control sweep attributed a safe-zone control to
`/dispatcher-chat`: that route was showing the home screen, control for
control. `chat_thread.js` had already noticed the shape — its header says "chat
routes redirect away without an alert so the screens had never actually" been
rendered — and the capture's own claim was never corrected to match.

`/lock` had the right treatment all along: it cannot be reached by URL, the
walk reaches it the way a person does, and a comment says why. These six cannot
have that treatment in this harness because each needs an incident another
harness creates. So they are named, excluded from the claim, and the claim says
where their real coverage lives.

## What this checks

The `URL_RENDERS_A_FALLBACK` map in `mobile_capture.js` matches what
`app_router.dart` actually does, in both directions:

1. Every route whose `pageBuilder` returns a different screen when its `extra`
   is null is listed — a new one cannot go unlisted and silently rejoin the
   completeness claim.
2. Every listed route still has such a fallback — a listing cannot outlive its
   subject and quietly exclude a screen that is now URL-reachable.
3. Each entry says which harness does drive it, so "covered elsewhere" is a
   claim with an address rather than a hope.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROUTER = REPO / 'lib/core/router/app_router.dart'
CAPTURE = REPO / 'scripts/local_e2e/mobile_capture.js'

router = ROUTER.read_text(encoding='utf-8')
capture = CAPTURE.read_text(encoding='utf-8')

# AppRoutes.<name> = '<path>'
paths = dict(re.findall(
    r"String\s+(\w+)\s*=\s*'([^']+)'", router))

# Every route whose pageBuilder falls back to another screen on a null extra.
falls_back: dict[str, str] = {}
for m in re.finditer(
        r'path:\s*AppRoutes\.(\w+),\s*pageBuilder:\s*\(c,\s*s\)\s*\{(.*?)\n\s*\},',
        router, re.S):
    name, body = m.group(1), m.group(2)
    fb = re.search(
        r'if\s*\(\s*\w+\s*==\s*null\s*\)\s*return\s*_\w+\(\s*s,\s*const\s+(\w+)\(\)\s*\)',
        body)
    if not fb:
        continue
    path = paths.get(name)
    if not path:
        print(f'AppRoutes.{name} has a fallback and no path constant — '
              'this check cannot map it')
        sys.exit(1)
    falls_back[path] = fb.group(1)

# The map as the capture declares it.
block = re.search(
    r'const URL_RENDERS_A_FALLBACK\s*=\s*\{(.*?)\n\s*\};', capture, re.S)
if not block:
    print('mobile_capture.js no longer declares URL_RENDERS_A_FALLBACK.\n'
          'Without it the walk counts a fallback screen as the screen the\n'
          'route names, and its completeness claim is false. See T-81.')
    sys.exit(1)
declared = dict(re.findall(r"'([^']+)':\s*'([^']*)'", block.group(1)))

findings: list[str] = []

for path, screen in sorted(falls_back.items()):
    if path not in declared:
        findings.append(
            f'{path} renders {screen} when reached by URL and is NOT listed, '
            'so the capture counts it as the screen it names')
        continue
    if 'driven by ' not in declared[path]:
        findings.append(
            f'{path} is listed without naming the harness that does drive it — '
            '"covered elsewhere" needs an address')

for path in sorted(set(declared) - set(falls_back)):
    findings.append(
        f'{path} is listed as rendering a fallback and no longer does — remove '
        'it, or it excludes a URL-reachable screen from the claim')

if findings:
    print('The capture\'s coverage claim does not match the router:\n')
    for item in findings:
        print(f'  * {item}')
    print()
    print('Update URL_RENDERS_A_FALLBACK in scripts/local_e2e/mobile_capture.js.')
    print('A screen that needs an incident cannot be rendered from a URL, and')
    print('counting the fallback makes the claim about "every screen" false.')
    print('See E2E_AUDIT_REPORT.md T-81.')
    sys.exit(1)

print('OK: the capture counts only the screens it actually rendered.')
print(f'  * {len(falls_back)} route(s) render a fallback by URL, all listed, '
      'each naming the harness that drives it')
print(f'  * the completeness claim covers the other '
      f'{len(set(paths.values())) - len(falls_back)} path(s) AppRoutes defines')
