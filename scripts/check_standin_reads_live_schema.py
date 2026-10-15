#!/usr/bin/env python3
"""The local stand-in must answer from the migrations as they are NOW.

    python3 scripts/check_standin_reads_live_schema.py

## What went wrong

`scripts/local_e2e/fake_supabase.js` rejects a column no migration defines, in
full, with a 400 — deliberately, because that is what PostgREST does and an
entire class of this system's defects was a screen naming a column that did not
exist. It read that column list ONCE, at require time:

    const { columns: schema } = require('./schema').build();

So a stand-in left running across a migration kept rejecting the column that
migration had just added. One was started at 13:06 and was still answering at
14:28, after `alerts.voice_note_url` had been added and the agency portal had
been given it to select. PostgREST's own behaviour then did the rest: the
whole query failed, the liaison desk came back with no incidents, and three
checks failed naming the portal and its buttons — on code that was fine.

It is the same trap as a stale `next-server` holding :3000 while `.next` is
rebuilt underneath it, which has cost this harness two invalidated runs. A
long-lived process answering from a snapshot of something that has since
changed does not report an error. It reports the PRODUCT broken, convincingly,
on the screen that depends on the thing that moved.

## What this checks

  * `schema.js` exports a `generation()` fingerprint, and that fingerprint is
    built from every migration's name, size and mtime — so an edit, an
    addition and a removal all move it. Checked against a fingerprint this
    script computes independently.
  * `fake_supabase.js` does not take its column list once at require time.
  * it has a refresh that compares `generation()` against what it loaded, and
    calls it in the REQUEST path — before anything is answered from the schema.

## What it does not check

That the schema is parsed correctly: `scripts/local_e2e/schema.js` run directly
prints what it found, and `check_schema_drift.py` compares the column names in
the app's source against the migrations. This checks only that what the
stand-in answers from is current.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCHEMA = REPO / 'scripts' / 'local_e2e' / 'schema.js'
FAKE = REPO / 'scripts' / 'local_e2e' / 'fake_supabase.js'
MIGRATIONS = REPO / 'supabase' / 'migrations'

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


schema_src = SCHEMA.read_text()
fake_src = FAKE.read_text()

# ---------------------------------------------------------------------------
# 1. The fingerprint exists, and moves when any migration does.
# ---------------------------------------------------------------------------
if not re.search(r'module\.exports\s*=\s*\{[^}]*\bgeneration\b', schema_src):
    fail(f'{SCHEMA.relative_to(REPO)} does not export `generation` — the '
         'stand-in has no cheap way to tell that the migrations have moved, '
         'and will keep answering from the set it read at boot.')
else:
    node = subprocess.run(
        ['node', '-e',
         "process.stdout.write(require(process.argv[1]).generation())",
         str(SCHEMA)],
        capture_output=True, text=True, cwd=REPO)
    if node.returncode != 0:
        fail(f'`generation()` would not run: {node.stderr.strip()[:300]}')
    else:
        got = node.stdout
        want = ''
        for sql in sorted(p.name for p in MIGRATIONS.glob('*.sql')):
            st = os.stat(MIGRATIONS / sql)
            want += f'{sql}:{st.st_size}:{st.st_mtime * 1000:.0f}\n'
        missing = [
            p.name for p in MIGRATIONS.glob('*.sql') if p.name not in got]
        if missing:
            fail('`generation()` leaves migrations out of its fingerprint, so '
                 'a change to one of them would not be noticed: '
                 f'{", ".join(sorted(missing)[:3])}')
        # mtime is read twice (here and in node) and must agree to the
        # millisecond; size and name are the parts that must be present.
        for sql in sorted(p.name for p in MIGRATIONS.glob('*.sql'))[:5]:
            size = os.stat(MIGRATIONS / sql).st_size
            if f'{sql}:{size}:' not in got:
                fail(f'`generation()` does not carry {sql}\'s size, so an '
                     'edit to it that keeps the mtime would not be noticed.')
                break
        if got and not re.search(r':\d{10,}', got):
            fail('`generation()` carries no mtime, so an edit to a migration '
                 'would not move it.')

# ---------------------------------------------------------------------------
# 2. The stand-in does not freeze the schema at require time.
# ---------------------------------------------------------------------------
FROZEN = re.compile(
    r"(?:const|let|var)\s*\{[^}]*\bcolumns\b[^}]*\}\s*=\s*require\("
    r"['\"]\./schema['\"]\)\.build\(\)")
if FROZEN.search(fake_src):
    fail(f'{FAKE.relative_to(REPO)} destructures the column list straight out '
         'of `require(\'./schema\').build()`, which freezes it at require '
         'time. A stand-in left running across a migration then rejects the '
         'column that migration adds — and the screen built on it comes back '
         'empty while the harness names the screen.')

# ---------------------------------------------------------------------------
# 3. There is a refresh, it compares the fingerprint, and the request path
#    calls it.
# ---------------------------------------------------------------------------
refresh = re.search(
    r'function\s+(refreshSchemaIfStale|[A-Za-z_$][\w$]*Stale[\w$]*)\s*\('
    r'[^)]*\)\s*\{', fake_src)
if not refresh:
    fail(f'{FAKE.relative_to(REPO)} has no staleness refresh. Add one that '
         'compares `generation()` against the fingerprint it loaded and '
         'rebuilds when they differ.')
else:
    name = refresh.group(1)
    # The body, to the matching brace.
    i = refresh.end()
    depth = 1
    while i < len(fake_src) and depth:
        if fake_src[i] == '{':
            depth += 1
        elif fake_src[i] == '}':
            depth -= 1
        i += 1
    body = fake_src[refresh.end():i - 1]
    if 'generation()' not in body:
        fail(f'`{name}` does not call `generation()`, so it cannot tell that '
             'the migrations have changed.')
    if not re.search(r'!==|!=', body):
        fail(f'`{name}` never compares the fingerprint it just read against '
             'the one it loaded, so it either rebuilds on every request or '
             'never rebuilds at all.')

    # The request handler, and the call inside it. The handler must consult the
    # refresh BEFORE it answers anything out of the schema — a refresh that
    # exists and is never called is the defect with extra code.
    handler = fake_src.find('http.createServer')
    if handler < 0:
        fail(f'{FAKE.relative_to(REPO)}: no `http.createServer` — this check '
             'cannot find the request path to confirm the refresh runs in it.')
    else:
        # To the start of the NEXT createServer (the control server), or the end.
        nxt = fake_src.find('http.createServer', handler + 1)
        region = fake_src[handler:nxt if nxt > 0 else len(fake_src)]
        if f'{name}(' not in region:
            fail(f'`{name}` is defined and never called in the request path, '
                 'so the stand-in still answers from the schema it read at '
                 'boot. Call it before the first read of `schema`.')

if failures:
    print('The stand-in can answer from a schema that is no longer on disk:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_standin_reads_live_schema.py for why this '
          'matters.')
    sys.exit(1)

print('The stand-in answers from the migrations as they are now:')
print(f'  * schema.js exports a generation() fingerprint over '
      f'{len(list(MIGRATIONS.glob("*.sql")))} migrations, carrying each '
      'name, size and mtime')
print('  * fake_supabase.js refills its column list rather than freezing it '
      'at require time')
print('  * and the request path consults the fingerprint before answering')
