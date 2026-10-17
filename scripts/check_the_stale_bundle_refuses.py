#!/usr/bin/env python3
"""The hand-assembled migration bundle must refuse to run.

    python3 scripts/check_the_stale_bundle_refuses.py

## What happened

An operator pasted `supabase/rainbow_full_migration.sql` into the SQL editor of
a live project. It died 1,385 lines in:

    ERROR: 42703: column "badge_number" does not exist
    LINE 1385:   badge_number,

The view at line 1385 selects `profiles.badge_number`; the only statement that
creates that column is an `ALTER TABLE` 1,231 lines further down. So the file
cannot run to completion on any database, empty or not — and nothing in CI
applies it, which is why nothing caught that. `scripts/verify_apply_all.sh`
proves `scripts/apply_all_migrations.sql`, a different file, generated from
`supabase/migrations/` and run twice against a production-shaped PostgreSQL.

The bundle already carried a warning at the top saying to prefer the generated
one. It was a COMMENT, and a comment cannot stop a paste: an operator selects
all, copies, and the first thing PostgreSQL does with a comment is ignore it.
Every document in this repository already points at the right file too. The
documentation was not the thing that failed.

So the file refuses in SQL instead, as its first statement — proved against a
real PostgreSQL 16: it raises at line 33, creates zero tables and exits 3.

## What this checks

  1. If the bundle exists, its first executable statement is a `DO` block that
     RAISEs, and the message names `scripts/apply_all_migrations.sql` so the
     operator is told where to go rather than only where not to be.
  2. No document tells an operator to paste the bundle. A refusal that fires
     after somebody has been sent there is a worse experience than not sending
     them, even though it is a safer one.

Deleting the file would also work. It is kept because T-13 and the policy
checks cite it by line number, and a finding that cannot be looked up is worth
less than a file that says no.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BUNDLE = REPO / 'supabase' / 'rainbow_full_migration.sql'
GENERATED = 'scripts/apply_all_migrations.sql'

failures: list[str] = []

if not BUNDLE.is_file():
    # Deleting it is a legitimate answer to the same problem.
    print('OK: the hand-assembled bundle is gone, which is one way to be safe.')
    raise SystemExit(0)

text = BUNDLE.read_text()

# The first thing that is not a comment or blank must be the refusal.
statement = ''
for line in text.split('\n'):
    stripped = line.strip()
    if not stripped or stripped.startswith('--'):
        continue
    statement = stripped
    break

if not statement.upper().startswith('DO'):
    failures.append(
        f'supabase/rainbow_full_migration.sql begins with {statement[:60]!r} '
        'rather than a DO block that refuses. A comment cannot stop a paste — '
        'that is exactly how this file reached a live project.')
else:
    # The DO block ITSELF, not the first few thousand characters. Checking a
    # window caught a deleted refusal and a downgraded one, and waved through a
    # refusal that had stopped naming the generated file — because the preamble
    # comment above it still mentioned the name, and the window could not tell
    # the two apart. Found by mutation-testing this check, not by reading it.
    block = re.search(r'\bDO\s*(\$\w*\$)(.*?)\1\s*;', text, re.S)
    body = block.group(2) if block else ''
    if 'RAISE EXCEPTION' not in body.upper():
        failures.append(
            'the opening DO block in supabase/rainbow_full_migration.sql does '
            'not RAISE. A block that runs quietly lets the paste continue into '
            'the 1,385-line failure.')
    if GENERATED not in body:
        failures.append(
            f'the refusal itself does not name {GENERATED}. Telling an '
            'operator they are in the wrong place without saying the right '
            'one leaves them to guess, in a SQL editor, against production. '
            '(A mention in the comment above does not count: PostgreSQL does '
            'not print comments, and the operator sees only the error.)')

# 2. Nothing may send an operator here in the first place.
PASTE = re.compile(
    r'(paste|run|apply|execute)[^.\n]{0,80}rainbow_full_migration', re.I)

# The audit report DESCRIBES the incident — "the operator pasted
# supabase/rainbow_full_migration.sql" — which this pattern cannot tell from an
# instruction to do it. Excluded by name rather than by trying to write a
# regex that distinguishes a narrative from an imperative, which is the kind of
# cleverness that fails silently later. It fired on this file the moment T-58
# was written into it, which is how the exclusion came to be here.
NARRATIVE = {'E2E_AUDIT_REPORT.md'}

docs = [d for d in sorted(REPO.glob('*.md')) + sorted((REPO / 'docs').glob('*.md'))
        if d.name not in NARRATIVE]
for doc in docs:
    for number, line in enumerate(doc.read_text().split('\n'), start=1):
        if PASTE.search(line):
            failures.append(
                f'{doc.relative_to(REPO)}:{number} tells an operator to run '
                'the hand-assembled bundle. It refuses, and it is the wrong '
                f'file: point at {GENERATED}.')

if failures:
    print('The stale migration bundle is reachable again:\n')
    for message in failures:
        print(f'  * {message}\n')
    sys.exit(1)

print('OK: the hand-assembled bundle refuses to run, and nothing points at it.')
print(f'  * its first statement is a DO block that RAISEs and names {GENERATED}')
print('  * no document in the repository tells an operator to paste it')
