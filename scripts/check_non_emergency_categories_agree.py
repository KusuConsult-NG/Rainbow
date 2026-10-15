#!/usr/bin/env python3
"""The app and the database must agree on which reports are not emergencies.

    python3 scripts/check_non_emergency_categories_agree.py

## What this protects

An operator asked for a general report: government property mismanaged,
vandalised, abandoned, unsafe, needing repair. That is not an emergency, and
this system is built to treat everything as one:

  * `queue_new_incident_notice()` announces every INSERT to the tier it landed
    at, and the drain widens a UNIT notice to the field responders — the people
    who physically go. A broken culvert filed at 02:00 would push to their
    handsets.
  * `escalate_overdue_alerts()` climbs anything unacknowledged one rung per
    timeout. Nobody acknowledges a street light at 02:00, so by morning it is
    an HQ-tier incident with three escalations against it, sitting among the
    night's actual emergencies.

`is_non_emergency(type)` is what stops both. It matches on the CATEGORY — the
part of `alerts.type` before ' - ' — against a list of labels, and those labels
come from the Flutter app: `type` is built as '<label> - <subtype>' in
`report_details_screen.dart`.

So the two lists are one list in two languages, and if they drift the failure
is silent and at night: a category the app can file and the database does not
recognise is routed, paged and escalated exactly like a kidnapping. Nothing
else would catch it — no test asserts the absence of a notification, and the
one that does assert routing uses a type string the test itself wrote.

## What it checks

Every `AlertCategoryInfo` in the app whose priority is LOW must be named in the
SQL function, and every label the SQL function names must exist in the app.
LOW is the app's own marker for "not an emergency" and the only one it has;
anything else would be a second vocabulary for the same idea.

## Why not derive one from the other

Because the SQL is applied to production by hand, from a migration, and the app
ships in a store. They move at different speeds and they cannot import each
other. A gate that fails the moment they disagree is the only thing that makes
them one list.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATEGORIES = REPO / 'lib' / 'core' / 'constants' / 'alert_categories.dart'
MIGRATIONS = REPO / 'supabase' / 'migrations'

if not CATEGORIES.exists():
    sys.exit(f'{CATEGORIES.relative_to(REPO)} is missing — it is the app half of '
             'this agreement.')

dart = CATEGORIES.read_text()

# Each entry is `AlertCategoryInfo( ... )`; read label and priority per entry.
app_low: dict[str, str] = {}
app_all: set[str] = set()
for block in re.finditer(r'AlertCategoryInfo\((.*?)\n  \)', dart, re.S):
    body = block.group(1)
    label = re.search(r"label:\s*'([^']+)'", body)
    priority = re.search(r"priority:\s*'([A-Z]+)'", body)
    if not label or not priority:
        continue
    app_all.add(label.group(1).upper())
    if priority.group(1) == 'LOW':
        app_low[label.group(1).upper()] = priority.group(1)

if not app_all:
    sys.exit('no categories parsed out of alert_categories.dart — the shape of '
             'that file changed and this check is reading nothing, which would '
             'pass for the wrong reason.')

# The SQL half: the latest migration that defines the function wins, the same
# way PostgreSQL resolves it.
# `\(` on the end, not a bare name: `is_non_emergency` is a PREFIX of
# `is_non_emergency_renamed`, so without it a rename that breaks every caller
# passed this check. Found by mutation-testing, which renamed the function and
# was waved through.
DEFINES = re.compile(
    r'CREATE OR REPLACE FUNCTION\s+(?:public\.)?is_non_emergency\s*\(')
defining = [
    p for p in sorted(MIGRATIONS.glob('*.sql'))
    if DEFINES.search(p.read_text())
]
if not defining:
    sys.exit('no migration defines is_non_emergency() — without it every report '
             'about public property is paged out to responders and climbed by '
             'the timeout sweep.')

sql = defining[-1].read_text()
# Comments blanked so the prose above the function — which quotes the labels —
# cannot satisfy the match.
sql_body = re.sub(r'--[^\n]*', '', sql)
match = re.search(
    r'FUNCTION\s+(?:public\.)?is_non_emergency\s*\(.*?IN\s*\(([^)]*)\)',
    sql_body, re.S)
if match is None:
    sys.exit(f'{defining[-1].name} defines is_non_emergency() but this check '
             'cannot find the list of categories in it. If the shape changed '
             'deliberately, change this check with it rather than leaving it '
             'reading nothing.')

sql_labels = {m.group(1).upper() for m in re.finditer(r"'([^']+)'", match.group(1))}

failures: list[str] = []

for label in sorted(app_low):
    if label not in sql_labels:
        failures.append(
            f'the app offers "{label}" at priority LOW and '
            f'{defining[-1].name} does not list it. A category the app can '
            'file and the database does not recognise is routed to the polling '
            'unit, pushed to the field responders\' handsets, and climbed by '
            'the timeout sweep — exactly like a kidnapping, at 02:00, for a '
            'street light.')

for label in sorted(sql_labels):
    if label not in app_all:
        failures.append(
            f'{defining[-1].name} names "{label}" and no category in the app '
            'has that label. Either the app renamed it — in which case every '
            'report filed under the new name is treated as an emergency — or '
            'the SQL is carrying a category nobody can file.')
    elif label not in app_low:
        failures.append(
            f'"{label}" is held out of the escalation ladder by the database '
            'but the app does not file it at priority LOW. One of the two is '
            'wrong about whether this is an emergency, and the screens read '
            'the app while the routing reads the database.')

if failures:
    print('The app and the database disagree about what is not an emergency:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_non_emergency_categories_agree.py for why this matters.')
    sys.exit(1)

print('The app and the database agree on what is not an emergency:')
print(f'  * {len(app_low)} LOW-priority categor(ies) in the app: '
      f'{", ".join(sorted(app_low))}')
print(f'  * the same {len(sql_labels)} in {defining[-1].name}, matched on the '
      'category before " - "')
print(f'  * {len(app_all)} categories in the app altogether')
