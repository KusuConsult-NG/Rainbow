#!/usr/bin/env python3
"""An incident's history is read from the log, not from prose.

    python3 scripts/check_history_reads_the_record.py

## What went wrong

`IncidentReplayPanel` — the forensic replay of one incident, the screen a
review reads — built its escalation events by string-matching the `ai_summary`
column:

    if (line.includes('[ESCALATED TO') || line.includes('[COMMAND ESCALATION]')) {
      combined.push({ type: 'ESCALATION', actor: 'Tactical Command',
                      timestamp: alert.updated_at || alert.created_at, notes: line });
    }

Three things follow from reading prose instead of the record:

  * **Every automatic escalation was missing.** `escalate_overdue_alerts()`
    appends to `escalation_log` and does not touch `ai_summary`, so an incident
    that climbed at 02:00 because nobody answered — the escalations nobody
    chose, and the ones a review most wants to see — appeared nowhere on the
    timeline. The Audit History screen showed them, because `audit_trail()`
    reads the log.
  * **Every escalation carried `updated_at`.** An incident escalated UNIT →
    WARD → LGA → HQ produced three events with one time, so the chronological
    sort could not order them and the chat messages sent between them landed in
    the wrong place.
  * **The actor was a literal** — `'Tactical Command'` for every escalation,
    while the log records who did it. T-32 was this exact fault in
    `audit_trail()`: it attributed every human action to SYSTEM, because it
    read only `by` and both clients write `by_email`. The fix there was to read
    the actor out of the entry; this screen never got the same treatment.

## What this checks

1. **Nobody reconstructs an escalation by matching prose.** The markers
   `[ESCALATED TO` and `[COMMAND ESCALATION]` may be WRITTEN — appending a
   human-readable line to `ai_summary` is how an operator sees what happened on
   the dossier — but not TESTED. A test of those markers is a history being
   rebuilt from a rendering of itself.

2. **One reading of an entry.** `entryActor` must try the same keys in the same
   order as `audit_trail()` in SQL: `by`, then `by_email`, then SYSTEM. The two
   are extracted and compared here, so a later change to either side that
   leaves them disagreeing fails rather than quietly giving the console and the
   audit screen different answers about who acted.

3. **No screen renders an unrecorded time as "Invalid Date".** A log entry with
   no `at` is a real shape — nothing validates the log's keys, and
   `audit_trail()` already falls back for it. `new Date(entry.at)` formatted
   straight onto a screen produces the string "Invalid Date", which reads as a
   broken console rather than as a gap in the record. `stampLabel` in
   `incident-timeline.ts` owns that wording.

## What it deliberately does not check

Whether `[MULTI-UNIT DISPATCH]` is read out of `ai_summary`. It is, in
`incident-timeline.ts`, and declared there: a dispatch has no structured log of
its own, and inventing a record for it on the way to the screen would be worse
than reading the prose. That gap is worth closing in the database, where the
other events live. The exemption is this one marker in that one file — a second
file reading it is the start of the same drift.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONSOLE = REPO / 'hq-dashboard-next' / 'src'
TIMELINE = CONSOLE / 'lib' / 'incident-timeline.ts'
MIGRATIONS = REPO / 'supabase' / 'migrations'

# Comments blanked rather than removed, so line numbers survive — including a
# multi-line /** ... */, which a line-at-a-time strip cannot see. This check's
# own prose quotes every defect it looks for, and so does the module's.
COMMENT = re.compile(r'/\*.*?\*/|//[^\n]*', re.S)
SQL_COMMENT = re.compile(r'/\*.*?\*/|--[^\n]*', re.S)


def blank(pattern: re.Pattern[str], text: str) -> str:
    return pattern.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)


def enclosing_coalesce(sql: str, inner: re.Pattern[str]) -> str | None:
    """The body of the `coalesce(...)` that contains `inner`.

    Read by counting parentheses rather than with one regex: the expression is
    `coalesce(nullif(e.entry ->> 'by', ''), nullif(...), 'SYSTEM')`, and a lazy
    pattern stops at the `)` that closes the first `nullif` — which reported
    the SQL as reading `by` alone and failed this check against a function that
    was correct.
    """
    hit = inner.search(sql)
    if hit is None:
        return None
    opened = sql.rfind('coalesce(', 0, hit.start())
    if opened == -1:
        return None
    depth = 0
    for index in range(opened + len('coalesce'), len(sql)):
        if sql[index] == '(':
            depth += 1
        elif sql[index] == ')':
            depth -= 1
            if depth == 0:
                return sql[opened + len('coalesce') + 1:index]
    return None


def sources() -> list[Path]:
    out: list[Path] = []
    for pattern in ('*.ts', '*.tsx'):
        out.extend(sorted(CONSOLE.rglob(pattern)))
    out.extend(sorted((REPO / 'lib').rglob('*.dart')))
    return [p for p in out if '.test.' not in p.name and not p.name.endswith('_test.dart')]


failures: list[str] = []

if not TIMELINE.exists():
    sys.exit(f'{TIMELINE.relative_to(REPO)} is missing — it owns the reading of an '
             'escalation entry, and this check has nothing to compare against '
             'without it.')

# ---- 1. the prose markers may be written, never matched ---------------------
MARKERS = ('[ESCALATED TO', '[COMMAND ESCALATION]')
# Reading a string: anything that asks whether the text contains something.
MATCHING = re.compile(
    r'\.(includes|indexOf|match|search|startsWith|endsWith|contains|test)\s*\(|'
    r'=~|RegExp\s*\(|\.split\s*\('
)

for path in sources():
    text = blank(COMMENT, path.read_text())
    for line_no, line in enumerate(text.splitlines(), start=1):
        if not any(marker in line for marker in MARKERS):
            continue
        if not MATCHING.search(line):
            continue  # Written, not read.
        failures.append(
            f'{path.relative_to(REPO)}:{line_no} — an escalation marker is being '
            'MATCHED, not written. `alerts.escalation_log` is the record of what '
            'happened to an incident; `ai_summary` carries a rendering of some of '
            'it. Rebuilding history from the rendering drops every escalation a '
            'timer performed, because `escalate_overdue_alerts()` writes no prose. '
            'Read the log — `escalationEvents` in lib/incident-timeline.ts.')

# ---- 2. one reading of who acted -------------------------------------------
timeline = blank(COMMENT, TIMELINE.read_text())

actor_fn = re.search(
    r'export function entryActor\([^)]*\)\s*:\s*string\s*\{(?P<body>.*?)\n\}',
    timeline,
    re.S,
)
if actor_fn is None:
    failures.append(
        'hq-dashboard-next/src/lib/incident-timeline.ts — `entryActor` is gone. '
        'It is the console\'s half of the agreement with `audit_trail()` about '
        'who performed an entry; without it there is nothing to keep in step.')
    console_order: list[str] = []
else:
    body = actor_fn.group('body')
    console_order = [
        m.group('key')
        for m in re.finditer(r"""entry\.(?P<key>\w+)|(?P<quote>['"])(?P<lit>SYSTEM)['"]""", body)
        if m.group('key')
    ]
    if re.search(r"""['"]SYSTEM['"]""", body):
        console_order.append('SYSTEM')

# The SQL side: the LAST migration that defines audit_trail() wins, the same way
# PostgreSQL resolves it.
sql_order: list[str] = []
defining = [
    p for p in sorted(MIGRATIONS.glob('*.sql'))
    if re.search(r'CREATE OR REPLACE FUNCTION\s+(public\.)?audit_trail', p.read_text())
]
if not defining:
    failures.append(
        'supabase/migrations — no migration defines `audit_trail()`. This check '
        'compares the console\'s reading of an escalation entry against that '
        'function\'s, and cannot do it against nothing. If the function was '
        'renamed, rename it here too rather than deleting the comparison.')
else:
    sql = blank(SQL_COMMENT, defining[-1].read_text())
    actor_sql = enclosing_coalesce(sql, re.compile(r"e\.entry\s*->>\s*'by'\s*,"))
    if actor_sql is None:
        failures.append(
            f'{defining[-1].relative_to(REPO)} — `audit_trail()` no longer reads '
            "the actor out of the entry with a coalesce over `by`. That is the "
            'T-32 fix: reading only one key attributed every human action to '
            'SYSTEM. If the shape changed deliberately, change `entryActor` in '
            'lib/incident-timeline.ts with it and update this check.')
    else:
        sql_order = [
            m.group(1) for m in re.finditer(r"e\.entry\s*->>\s*'(\w+)'", actor_sql)
        ]
        if re.search(r"'SYSTEM'", actor_sql):
            sql_order.append('SYSTEM')

if sql_order and console_order and sql_order != console_order:
    failures.append(
        'The console and the audit trail disagree about who performed an '
        f'escalation. audit_trail() reads {" then ".join(sql_order)}; '
        f'entryActor() reads {" then ".join(console_order)}. The SQL writers set '
        '`by`, both clients set `by_email`, and a screen that reads one of them '
        'names the wrong party for half the history (T-32).')

# ---- 3. an unrecorded time is said, not rendered ---------------------------
#
# `new Date(<entry>.at)` handed straight to a locale formatter. Only the
# timeline module may format a log entry's time, because it is where the
# wording for not having one lives.
RAW_STAMP = re.compile(r'new Date\(\s*[A-Za-z_$][\w.$?\[\]\'"]*\.at\b[^)]*\)\s*\.\s*toLocale')

for path in sources():
    if path == TIMELINE or path.suffix == '.dart':
        continue
    text = blank(COMMENT, path.read_text())
    for match in RAW_STAMP.finditer(text):
        line_no = text[:match.start()].count('\n') + 1
        failures.append(
            f'{path.relative_to(REPO)}:{line_no} — a log entry\'s `at` is formatted '
            'directly. An entry with no `at` is a real shape, and '
            '`new Date(undefined).toLocaleString()` is the string "Invalid Date" — '
            'which reads as a broken console rather than as a gap in the record. '
            'Use `stampLabel` from lib/incident-timeline.ts.')

if failures:
    print('An incident\'s history is not being read from the record:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_history_reads_the_record.py for why this matters.')
    sys.exit(1)

print('Incident history is read from the record:')
print(f'  * no screen matches {len(MARKERS)} escalation marker(s) out of `ai_summary`')
print(f'  * audit_trail() and entryActor() both read {" then ".join(sql_order)}')
print('  * every rendered log timestamp goes through `stampLabel`, which says '
      'when a time\n    was never recorded')
