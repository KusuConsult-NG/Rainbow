#!/usr/bin/env python3
"""Every table the product reads must be one the local run actually serves.

    python3 scripts/check_the_harness_serves_every_table.py

## What went wrong

The local stand-in resolved a table like this:

    let rows = (tables[table] || []).slice();   // read
    if (tables[table]) tables[table].push(row); // write

A table `fixtures.js` did not declare therefore read as **empty** and wrote as
**201 Created with the row echoed back and nothing stored**. The client saw
success. The table never had the row.

Five tables the shipped product reads were in exactly that state:

    safe_zones           the shelters a citizen is routed to
    incident_tracks      the live route a dispatcher follows
    sim_channel_events   the SIM-swap signal HQ reads
    incident_ai_reports  written by the console's AI route
    ussd_sessions        the state of a USSD caller's session

`incident_tracks` is the one that matters most. Following the device during an
emergency is what the whole tracking pass was for, and the harness had never
stored a single point of it — every insert accepted, every read empty. A
screen photographed blank and a screen built on a table the stand-in had never
heard of look identical, which is how this survived a green run.

The stand-in already treats an unknown COLUMN as a 400, on purpose, because a
tolerant fake turns a defect into a pass. An unknown TABLE was the same mistake
one level up.

## What this checks

1. Every table read with `.from('x')` in `lib/` (the app) or in
   `hq-dashboard-next/src/` (the console) is declared in `fixtures.js`.
2. Every table those fixtures declare exists in `supabase/migrations/`, so the
   run cannot serve a column production has never had.
3. `fake_supabase.js` still rejects a table no migration creates, rather than
   answering it empty.

Declaring a table EMPTY is a legitimate answer — a USSD session begins when
somebody dials. What is not legitimate is the harness not knowing it exists.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FIXTURES = REPO / 'scripts/local_e2e/fixtures.js'
FAKE = REPO / 'scripts/local_e2e/fake_supabase.js'

FROM = re.compile(r"""\.from\(\s*['"]([a-z_][a-z0-9_]*)['"]\s*\)""")

# Where the product reads its data, and what counts as product code there.
SOURCES = [
    (REPO / 'lib', ('*.dart',), 'the app'),
    (REPO / 'hq-dashboard-next/src', ('*.ts', '*.tsx'), 'the console'),
]

# A test's own stub tables are not the product reading a table.
SKIP = re.compile(r'\.(test|spec)\.(ts|tsx|dart)$|/__tests__/|/test/')


def declared_tables() -> set[str]:
    """The tables `fixtures.js` serves, read by asking node rather than regex."""
    out = subprocess.run(
        ['node', '-e',
         "process.stdout.write(JSON.stringify("
         "Object.keys(require('./scripts/local_e2e/fixtures.js').tables)))"],
        cwd=REPO, capture_output=True, text=True, check=False)
    if out.returncode != 0:
        print('fixtures.js could not be loaded:\n' + out.stderr.strip())
        sys.exit(1)
    return set(json.loads(out.stdout))


def migrated_tables() -> set[str]:
    out = subprocess.run(
        ['node', '-e',
         "process.stdout.write(JSON.stringify("
         "Object.keys(require('./scripts/local_e2e/schema.js').build().columns)))"],
        cwd=REPO, capture_output=True, text=True, check=False)
    if out.returncode != 0:
        print('schema.js could not be loaded:\n' + out.stderr.strip())
        sys.exit(1)
    return set(json.loads(out.stdout))


served = declared_tables()
migrated = migrated_tables()

# table -> first place the product reads it
wanted: dict[str, str] = {}
files_read = 0
for root, globs, which in SOURCES:
    if not root.is_dir():
        continue
    for pattern in globs:
        for path in sorted(root.rglob(pattern)):
            rel = str(path.relative_to(REPO))
            if SKIP.search(rel) or '/node_modules/' in rel or '/.next/' in rel:
                continue
            files_read += 1
            text = path.read_text(encoding='utf-8', errors='replace')
            for match in FROM.finditer(text):
                table = match.group(1)
                if table in wanted:
                    continue
                line = text[:match.start()].count('\n') + 1
                wanted[table] = f'{rel}:{line}  ({which})'

findings: list[str] = []

for table, where in sorted(wanted.items()):
    if table in served:
        continue
    if table not in migrated:
        findings.append(
            f'{table} — read at {where}, and NO migration creates it')
    else:
        findings.append(
            f'{table} — read at {where}, not declared in fixtures.js')

for table in sorted(served - migrated):
    findings.append(
        f'{table} — declared in fixtures.js, but no migration creates it')

# The stand-in's own half of the guarantee. Without this the fixtures can be
# complete today and the next undeclared table is served empty again.
fake = FAKE.read_text(encoding='utf-8')
if 'unknownTables' not in fake:
    findings.append(
        'fake_supabase.js no longer tracks unknown tables — a table no '
        'migration creates would be answered empty instead of 404')
elif 'PGRST205' not in fake:
    findings.append(
        'fake_supabase.js tracks unknown tables but no longer answers the '
        "404 PostgREST answers (PGRST205), so a run cannot see it")

if findings:
    print('The local run does not serve every table the product reads:\n')
    for item in findings:
        print(f'  {item}')
    print()
    print('An undeclared table reads EMPTY and writes 201 with the row')
    print('dropped, so a screen built on it photographs blank and a harness')
    print('cannot tell that from a feature nobody has written. Declare it in')
    print('scripts/local_e2e/fixtures.js — empty is a fine answer, not')
    print('knowing it exists is not. See E2E_AUDIT_REPORT.md T-75.')
    sys.exit(1)

print('OK: every table the product reads is one the local run serves.')
print(f'  * {len(wanted)} tables read across {files_read} app and console files')
print(f'  * {len(served)} declared in fixtures.js, all of them in the migrations')
print('  * a table no migration creates is still a 404 from the stand-in')
