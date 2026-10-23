#!/usr/bin/env python3
"""A migration that only rewrites a function body must still be detectable.

    python3 scripts/check_the_inventory_sees_a_new_body.py

## What went wrong

An operator ran `scripts/which_migrations_are_applied.sql` against the live
project to find out what it was missing, and got this for the migration that
was the reason eight of their ten commanders could not post an advisory:

    not detectable | 20261028000000_command_knows_both_vocabularies |
      every object it declares is already created by an earlier migration, so
      it is a no-op on a database that has them

True, and useless. That migration replaces `is_command` and
`commands_whole_state`; both functions exist either way, so object existence
had nothing to count and the file dropped out of the report. There were SIXTEEN
such replacements in the history and the diagnostic could see none of them,
including:

  * `20260927000000_signup_cannot_choose_role`, whose entire change is deleting
    `COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')` from
    `handle_new_user` so that a new account cannot name its own role. An
    operator could not tell whether that was applied.
  * `20261019000000_the_audit_trail_names_who_acted`, which rewrites
    `audit_trail` — a function the console calls by name.

The same shape as every other gap in this inventory: a check that reads a
subset of its subject. Here the subset was "objects that exist", and the thing
it could not see was the only thing several migrations change.

PostgreSQL keeps the body: `pg_proc.prosrc` holds the text between the dollar
quotes verbatim. So "is the new body installed?" is answerable, by looking for
a token only that version of the body contains — extracted from the migrations
rather than written down, like the rest of the inventory.

## What this checks

1. Every function a later migration replaces is accounted for: it has a
   `function body` row, or its body is byte-identical to the one before it and
   the migration says so under `not detectable`.
2. Every token still holds in the FINAL body. A fingerprint taken from a
   migration that a later one rewrote again would report the newest migration
   applied and an older one missing — sending somebody to re-apply a file that
   is already in. This is the assertion, not the extractor's own later-body
   filter: dropping that filter leaves today's output byte-identical, because
   the longest new token happens to survive in every case. The property has to
   be checked where it matters rather than where it is implemented.
3. The generated SQL carries the predicate and the two readable formatters.
   Emitting the rows without the `WHEN 'function body'` branch makes `present`
   NULL, which reads as NEVER APPLIED for every one of them.
4. The two migrations this was found through are covered by name.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'scripts'))

from sync_migration_inventory import (  # noqa: E402
    MIGRATIONS, function_bodies, inventory, strip_comments)

GENERATED = REPO / 'scripts' / 'which_migrations_are_applied.sql'

# Found through these two. Named so that a change which stops detecting either
# fails here rather than in somebody's production report.
MUST_BE_SEEN = {
    '20261028000000_command_knows_both_vocabularies':
        'the reason a STATE_COMMANDER could not post an advisory',
    '20260927000000_signup_cannot_choose_role':
        'the reason a new signup cannot write its own role',
}

faults: list[str] = []

declarations: dict[str, list[tuple[str, str]]] = {}
for path in sorted(MIGRATIONS.glob('*.sql')):
    for name, body in function_bodies(strip_comments(path.read_text())).items():
        declarations.setdefault(name, []).append((path.stem, body))

rows, undetectable = inventory()
body_rows = [r for r in rows if r[1] == 'function body']
by_migration: dict[str, list[tuple[str, str, bool]]] = {}
for stem, _, obj, want in body_rows:
    fn, token = obj.split(':', 1)
    by_migration.setdefault(stem, []).append((fn, token, want))

# ── 1. every replacement is accounted for ───────────────────────────────────
accounted = {(stem, fn) for stem, rs in by_migration.items() for fn, _, _ in rs}
undetectable_reasons = dict(undetectable)
for fn, seq in sorted(declarations.items()):
    for at in range(1, len(seq)):
        stem, body = seq[at]
        prev_stem, prev = seq[at - 1]
        if prev_stem == stem:
            continue        # two overloads in one file, not a replacement
        if (stem, fn) in accounted:
            continue
        if body.strip() == prev.strip():
            # Nothing to detect, and the migration has to SAY that rather than
            # claim its objects were already created.
            why = undetectable_reasons.get(stem, '')
            if stem in undetectable_reasons and 'same body' not in why:
                faults.append(
                    f'{stem} re-declares {fn} with an identical body, and is '
                    f'reported as "{why}" — which is a different claim and '
                    f'leaves the reader looking for an object.')
            continue
        faults.append(
            f'{stem} replaces {fn} with a different body and no `function '
            f'body` row was emitted, so nothing can tell whether the new body '
            f'is the one installed.')

# ── 2. every token still holds in the final body ────────────────────────────
for stem, rs in sorted(by_migration.items()):
    for fn, token, want in rs:
        final = declarations[fn][-1][1]
        if want and token not in final:
            faults.append(
                f'{stem}: the fingerprint {token} for {fn} is not in the body '
                f'a later migration leaves installed. The inventory would '
                f'report this migration missing on a database that has every '
                f'one of them, and send somebody to re-apply it.')
        if not want and token in final:
            faults.append(
                f'{stem}: {fn} is asserted NOT to contain {token}, and the '
                f'final body does. The assertion can never pass.')

# ── 3. the generated SQL can evaluate the rows ──────────────────────────────
#
# Read the QUERY, not the file. The header explains these rows and quotes an
# example line — `function is_command does not contain 'STATE_COMMANDER'` — so
# a check that greps the whole file is satisfied by its own documentation. The
# first version of this did exactly that, and passed with the formatter deleted
# from the template. Hence the `format(` prefixes below, which are the call and
# cannot be prose.
sql = GENERATED.read_text(encoding='utf-8')
query = sql[sql.index('WITH expected('):] if 'WITH expected(' in sql else ''
if not query:
    faults.append('the generated diagnostic has no `WITH expected(` to read; '
                  'this check cannot tell the query from the header.')
if body_rows and query:
    for needed, why in (
        ("WHEN 'function body' THEN", 'no `function body` branch'),
        ('p.prosrc', 'no read of p.prosrc, the column that holds the body'),
        ("format('function %s does not contain %s'",
         'no formatter for the `missing` line'),
        ("format('function %s still contains %s'",
         'no formatter for the `still present` line'),
    ):
        if needed not in query:
            faults.append(
                f'the generated diagnostic has {len(body_rows)} `function '
                f'body` rows and {why} ({needed!r}). Without the predicate '
                f'`present` is NULL for every one of them, which reads as '
                f'NEVER APPLIED — a false alarm on a correct database.')

# ── 4. the two it was found through ─────────────────────────────────────────
for stem, what in sorted(MUST_BE_SEEN.items()):
    if stem not in by_migration:
        faults.append(
            f'{stem} has no `function body` row. It is {what}, it creates '
            f'nothing, and without that row the report says "not detectable" '
            f'for it — which is what sent somebody looking in the wrong place.')

if faults:
    print('FAIL: a replaced function body is not detectable.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-91.')
    sys.exit(1)

print(f'OK: {len(body_rows)} replaced function bodies are detectable, across '
      f'{len(by_migration)} migrations.')
for stem, rs in sorted(by_migration.items()):
    for fn, token, want in sorted(rs):
        print(f'  * {stem}: {fn} '
              f'{"contains" if want else "no longer contains"} {token}')
