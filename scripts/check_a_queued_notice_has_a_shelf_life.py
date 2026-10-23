#!/usr/bin/env python3
"""An emergency notice must not be deliverable after its moment has passed.

    python3 scripts/check_a_queued_notice_has_a_shelf_life.py

## What went wrong

The live project's queue, read in October:

    outbox_rows 412 | outbox_pending 412 | outbox_erroring 0 | max attempts 0

Four hundred and twelve notifications, not one ever attempted, the oldest from
July. The drain worker had never been scheduled. Scheduling it was the obvious
next step, and `claim_notifications` took the oldest rows whose
`next_attempt_at` had passed with NO upper bound on age — not in the function,
not in `supabase/functions/drain-outbox/index.ts`, not in the console's
`/api/notify/drain`. So the first thing a newly scheduled worker would do is
deliver July, twenty notices a minute for twenty-one minutes, each one reading

    INCIDENT NOW AT LGA
    Incident #a3f2b118 in JOS SOUTH was not acknowledged in time and has come
    up to LGA. Open the console to take it.

about incidents that are closed. Indistinguishable from a live notice, because
that is what the wording is for.

A notification about an emergency is an instruction to go somewhere, and it
decays. There is no retry policy under which delivering a three-month-old tier
escalation beats dropping it.

## What this checks

1. Neither drainer finds its own work. Both must go through
   `claim_notifications`, because that is the one place the shelf life is
   applied — and there are two drainers, so a rule written twice drifts. This
   project has already had that exact bug: the OneSignal auth scheme was
   written four times, and at most one copy ever authenticated.
2. `claim_notifications` excludes retired rows and expires BEFORE its LIMIT.
   Expiring inside the claim CTE is the natural implementation and it gives the
   queue a warm-up period: one tick per batch of stale rows, so with 412
   standing the first live notice waits twenty-one minutes.
3. Retiring a notice never writes `delivered_at`. The outbox exists because a
   worker once marked escalations delivered with nobody told; recording a
   dropped notice as sent would put that back in the one table whose honesty
   this mechanism is for.
4. Every query that counts the queue excludes retired rows. Two of them did not
   when this was written — `worst_attempts` and `newest_error` in
   why_is_the_board_empty.sql — so a retired row's old failure would have been
   reported as the newest thing wrong with a queue nobody was draining.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SHELF_LIFE = REPO / 'supabase/migrations/20261029000000_a_notification_has_a_shelf_life.sql'
DRAINERS = (
    REPO / 'supabase/functions/drain-outbox/index.ts',
    REPO / 'hq-dashboard-next/src/app/api/notify/drain/route.ts',
)

faults: list[str] = []
proved: list[str] = []


def sql_code(text: str) -> str:
    """Blank `--` comments, keeping line positions."""
    return '\n'.join(re.sub(r'--.*$', '', line) for line in text.split('\n'))


if not SHELF_LIFE.is_file():
    print(f'FAIL: {SHELF_LIFE.relative_to(REPO)} is missing — the shelf life is '
          f'the only thing standing between a scheduled drainer and three '
          f'months of false alerts.')
    sys.exit(1)

shelf = sql_code(SHELF_LIFE.read_text(encoding='utf-8'))

# ── 1. neither drainer finds its own work ───────────────────────────────────
for path in DRAINERS:
    if not path.is_file():
        faults.append(f'{path.relative_to(REPO)} is missing')
        continue
    src = path.read_text(encoding='utf-8')
    if 'claim_notifications' not in src:
        faults.append(
            f'{path.relative_to(REPO)} does not call `claim_notifications`. '
            f'That is the one place a notice is checked against its shelf '
            f'life; a drainer that selects its own work sends the backlog.')
    # A `.select(` on the table is how a drainer would find work for itself.
    # `.update(` on it is how it records an outcome, and stays allowed.
    for m in re.finditer(r"from\(\s*['\"]notification_outbox['\"]\s*\)([\s\S]{0,120})",
                         src):
        if '.select(' in m.group(1):
            line = src.count('\n', 0, m.start()) + 1
            faults.append(
                f'{path.relative_to(REPO)}:{line} selects from '
                f'`notification_outbox` directly. Work must come from '
                f'`claim_notifications`, or this drainer has no shelf life.')
if not faults:
    proved.append('both drainers take their work from claim_notifications')

# ── 2. the claim excludes retired rows, and expires before its LIMIT ────────
claim = re.search(
    r'CREATE OR REPLACE FUNCTION public\.claim_notifications\(.*?\n\$\$;',
    shelf, re.S)
if claim is None:
    faults.append(
        '20261029000000 does not replace `claim_notifications`. The shelf life '
        'has to be enforced where work is handed out, not in each worker.')
else:
    body = claim.group(0)
    if 'expired_at IS NULL' not in body:
        faults.append(
            '`claim_notifications` does not exclude retired rows, so a notice '
            'is retired and then handed out anyway.')
    sweep = body.find('expire_stale_notifications')
    limit = body.find('LIMIT')
    if sweep < 0:
        faults.append(
            '`claim_notifications` never expires anything. A caller that '
            'forgets to sweep first delivers the backlog, and there are two '
            'callers.')
    elif limit >= 0 and sweep > limit:
        faults.append(
            '`claim_notifications` expires stale notices AFTER its LIMIT, so '
            'the worker spends one tick per batch of them. With the 412 '
            'standing on the live project the first real notice waits '
            'twenty-one minutes — an emergency queue cannot have a warm-up '
            'period.')
    else:
        proved.append('the claim retires the backlog before taking its batch, '
                      'unbounded, so a live notice is never queued behind it')

# ── 3. retiring is not recording a delivery ─────────────────────────────────
expire = re.search(
    r'CREATE OR REPLACE FUNCTION public\.expire_stale_notifications\(.*?\n\$\$;',
    shelf, re.S)
if expire is None:
    faults.append('there is no `expire_stale_notifications` to sweep with')
elif re.search(r'delivered_at\s*=', expire.group(0)):
    faults.append(
        '`expire_stale_notifications` writes `delivered_at`. Nobody was told. '
        'The outbox exists because a worker once marked escalations delivered '
        'with nobody told, and writing that here puts it back.')
else:
    proved.append('a retired notice is not recorded as delivered')

# ── 4. every count of the queue skips retired rows ──────────────────────────
#
# Checked across the repository rather than in the file that had the bug,
# because the bug WAS a query that read a subset of its subject.
#
# Scoped to the enclosing SUBQUERY, not to a window of characters. The first
# version of this read 400 characters either side, and
# why_is_the_board_empty.sql puts five of these scalar subqueries one after
# another — so reverting any single one of them still passed, satisfied by its
# neighbour's `expired_at`. A proximity check on adjacent near-identical
# queries is not a check.
PENDING = re.compile(r'delivered_at\s+IS\s+NULL', re.I)


def enclosing_query(text: str, pos: int) -> str:
    """The parenthesised subquery around `pos`, or its statement if top-level."""
    depth, opener = 0, None
    for i in range(pos - 1, -1, -1):
        if text[i] == ')':
            depth += 1
        elif text[i] == '(':
            if depth == 0:
                opener = i
                break
            depth -= 1
    if opener is None:
        start = text.rfind(';', 0, pos) + 1
        end = text.find(';', pos)
        return text[start:end if end >= 0 else len(text)]
    depth = 0
    for j in range(opener, len(text)):
        if text[j] == '(':
            depth += 1
        elif text[j] == ')':
            depth -= 1
            if depth == 0:
                return text[opener:j + 1]
    return text[opener:]
for path in sorted(REPO.rglob('*.sql')):
    rel = str(path.relative_to(REPO))
    # The generated bundles are concatenations of the migrations, and the
    # pre-shelf-life migration is history: it is the file this one replaces.
    if ('apply_in_parts' in rel or rel.endswith('apply_all_migrations.sql')
            or rel.endswith('bootstrap_staging.sql')
            or rel.endswith('rainbow_full_migration.sql')
            or '20261007000000' in rel or '20261029000000' in rel):
        continue
    text = sql_code(path.read_text(encoding='utf-8', errors='replace'))
    for m in PENDING.finditer(text):
        line = text.count('\n', 0, m.start()) + 1
        if 'expired_at' not in enclosing_query(text, m.start()):
            faults.append(
                f'{rel}:{line} counts a notice as pending on `delivered_at IS '
                f'NULL` alone, so a notice retired undelivered is still '
                f'reported as owed. After the sweep this reads the same 412.')
if not any('counts a notice as pending' in f for f in faults):
    proved.append('every query that counts the queue skips retired notices')

if faults:
    print('FAIL: a queued notice can outlive its moment.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-92.')
    sys.exit(1)

print('OK: a queued notice has a shelf life, enforced where work is handed out.')
for item in proved:
    print(f'  * {item}')
