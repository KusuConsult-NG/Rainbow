#!/usr/bin/env python3
"""A real ward must resolve to itself, and replacing an indexed function must
rebuild the index.

    python3 scripts/check_a_ward_name_resolves.py

## What went wrong

The live project files incidents under `JOS SOUTH / BUKURU` and under
`JOS SOUTH / BUKURU WARD` as if they were different places, and carries
`BUKURU WARD` as the posting of staff in six different LGAs. `BUKURU` is a ward
of Jos South and of nowhere else, and **not one of the 207 surveyed ward names
ends in " WARD"**: the suffix is the word the form already said.

`alert_in_my_area()` compares a posting with an incident through `geo_key()`,
which upper-cases, collapses whitespace and rewrites a trailing Roman numeral —
and did not touch a trailing " WARD". So `geo_key('BUKURU') <> geo_key('BUKURU
WARD')`, a ward commander posted to one was refused every incident filed at the
other, and their board was empty with the rows right there.

## The second thing, which is worse

`geo_key()` is IMMUTABLE and `20261009000000` INDEXES it:

    CREATE INDEX alerts_geo_key_idx
      ON public.alerts (geo_key(geo_lga), geo_key(geo_ward), geo_key(geo_pu));

IMMUTABLE is a promise that one input always gives one output, and PostgreSQL
believes it: the index keeps values computed under the OLD body and is not
rebuilt when the function is replaced. An index scan then looks up `'BUKURU'`
among keys stored as `'BUKURU WARD'` and finds nothing — so a migration that
replaces the function without reindexing leaves the bug in place for the queries
that use the index while a sequential scan returns the right answer. The same
query, right or wrong by plan.

Nothing in this repository said so, and T-91 had just made function-body
replacements visible — sixteen of them — so the next one to touch an indexed
function would have hit this.

## What this checks

1. Under the CURRENT `geo_key`, no two of the surveyed LGA/ward pairs collide.
   The strip is safe only because it has nothing real to collide with, and the
   day a ward called "X WARD" is added this says so rather than two wards
   quietly becoming one.
2. The strip actually happens: `BUKURU` and `BUKURU WARD` resolve together, and
   `JOS SOUTH` and `JOS SOUTH LGA` do. Without this, 1 passes vacuously.
3. Every real ward still resolves to a non-empty key. A regex that emptied a
   name would make that ward match nothing at all.
4. Any migration that replaces an IMMUTABLE function which an index is built on
   REINDEXes that index, by name.

The normalisation is not reimplemented here. The `regexp_replace` patterns are
EXTRACTED from the migration body in application order and applied, so this
check cannot drift from the function it is checking — which is the mistake that
made the Roman-numeral comparison wrong in two places at once.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / 'scripts'))

from sync_migration_inventory import (  # noqa: E402
    MIGRATIONS, function_bodies, strip_comments)

ASSET = REPO / 'assets' / 'geo' / 'plateau_wards.json'

faults: list[str] = []
proved: list[str] = []

# ── the current geo_key, lifted out of the migration that defines it last ───
latest_body: str | None = None
for path in sorted(MIGRATIONS.glob('*.sql')):
    bodies = function_bodies(strip_comments(path.read_text(encoding='utf-8')))
    if 'geo_key' in bodies:
        latest_body = bodies['geo_key']
if latest_body is None:
    print('FAIL: no migration defines geo_key(). It is what RLS compares place '
          'names with.')
    sys.exit(1)

# `regexp_replace(X, 'pattern', 'replacement')` — in textual order, which for
# this nesting style IS application order: the innermost call is written first.
STEP = re.compile(r"regexp_replace\(\s*(?:.|\n)*?'((?:[^']|'')*)'\s*,\s*"
                  r"'((?:[^']|'')*)'(?:\s*,\s*'((?:[^']|'')*)')?\s*\)")
steps: list[tuple[str, str, str]] = []
for m in re.finditer(r"'((?:[^']|'')*)'\s*,\s*'((?:[^']|'')*)'"
                     r"(?:\s*,\s*'((?:[^']|'')*)')?\s*\)", latest_body):
    pattern = m.group(1).replace("''", "'")
    repl = m.group(2).replace("''", "'")
    flags = (m.group(3) or '').replace("''", "'")
    steps.append((pattern, repl, flags))
# The final `nullif(..., '')` contributes a pair whose "pattern" is empty.
steps = [s for s in steps if s[0]]
if len(steps) < 4:
    faults.append(
        f'only {len(steps)} regexp_replace step(s) read out of geo_key. This '
        f'check applies the function by extracting its own patterns, and '
        f'reading fewer than it has would make every assertion below weaker '
        f'than the function it is checking.')


def geo_key(name: str | None) -> str | None:
    """geo_key(), applied from the patterns in the migration itself."""
    out = re.sub(r'\s+', ' ', (name or '').strip().upper())
    for pattern, repl, flags in steps:
        # PostgreSQL writes a backreference \1; Python's sub takes the same.
        out = re.sub(pattern, repl, out,
                     count=0 if 'g' in flags else 1)
    return out or None


# ── 1 & 3. the surveyed wards resolve, and distinctly ───────────────────────
wards = json.loads(ASSET.read_text(encoding='utf-8'))['wards']
keyed: dict[tuple[str | None, str | None], list[str]] = {}
for w in wards:
    where = f"{w['lga']}/{w['ward']}"
    key = (geo_key(w['lga']), geo_key(w['ward']))
    if key[0] is None or key[1] is None:
        faults.append(
            f'{where} resolves to {key}, so that ward matches nothing at all. '
            f'A normalisation that can empty a real name blinds whoever is '
            f'posted to it.')
    keyed.setdefault(key, []).append(where)

for key, places in sorted(keyed.items()):
    if len(places) > 1:
        faults.append(
            f'{len(places)} surveyed wards resolve to the same key {key}: '
            f'{", ".join(places)}. RLS compares postings and incidents by this '
            f'key, so an officer posted to one of them would see the other\'s '
            f'incidents.')
if not faults:
    proved.append(f'all {len(wards)} surveyed wards resolve, and to '
                  f'{len(keyed)} distinct keys')

# ── 2. and the suffix is genuinely dropped ──────────────────────────────────
for a, b, what in (
    ('BUKURU', 'BUKURU WARD', 'a ward and the same ward with WARD after it'),
    ('JOS SOUTH', 'JOS SOUTH LGA', 'an LGA and the same LGA with LGA after it'),
    ('BUKURU', 'BUKURU   WARD', 'the suffix after a run of spaces'),
    ('GINDIRI I', 'GINDIRI 1', 'the Roman numeral 20261009000000 was written for'),
):
    if geo_key(a) != geo_key(b):
        faults.append(
            f'{what} do not resolve together: geo_key({a!r}) = '
            f'{geo_key(a)!r} and geo_key({b!r}) = {geo_key(b)!r}. A ward '
            f'officer posted to one is refused every incident filed at the '
            f'other, and their board is empty with the rows right there.')
# A name that is only the stripped word must survive: emptying it would make
# that place match nothing.
if geo_key('WARD') != 'WARD':
    faults.append(
        f"geo_key('WARD') is {geo_key('WARD')!r}. The strip needs a character "
        f"and a space in front of the suffix, or a place whose whole name is "
        f"the word is erased.")
if not any('resolve together' in f for f in faults):
    proved.append('BUKURU and BUKURU WARD resolve together, and so do '
                  'JOS SOUTH and JOS SOUTH LGA')

# ── 4. replacing an indexed IMMUTABLE function rebuilds the index ───────────
#
# Read across every migration, not just the one that prompted this: the point is
# the next person to replace an indexed function, not this one.
#
# TWO regex mistakes here, both found by reading what the check REPORTED.
#
# `ON public.alerts (public.geo_key(geo_lga), ...)` has two `public.x(` in it
# and the first is the table, so a lazy `[^;]*?\bpublic\.(\w+)\s*\(` captured
# `alerts`. Check 4 then found no indexed function at all and printed "0 indexed
# IMMUTABLE function(s)", which is the line that gave it away.
#
# Capturing the column list with `\((.*?)\)\s*;` was the second: a partial
# index ends `WHERE reporter_msisdn IS NOT NULL;` with no `)` before the
# semicolon, so the lazy match ran past that statement into the next one and
# attributed its index to unrelated functions.
#
# So the parentheses are scanned, balanced, and the WHERE predicate is read too
# — a partial index's predicate decides which rows are IN the index, so a
# predicate built on a replaced IMMUTABLE function is stale in the same way and
# in a worse direction: rows silently missing rather than keys not found.
INDEX_HEAD = re.compile(
    r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s+ON\s+'
    r'(?:public\.)?\w+\s*(?=\()', re.I)
BUILT_ON = re.compile(r'public\.(\w+)\s*\(', re.I)


def index_definitions(code: str) -> list[tuple[str, str]]:
    """[(index name, everything it is built from), ...]"""
    out: list[tuple[str, str]] = []
    for m in INDEX_HEAD.finditer(code):
        i, depth = m.end(), 0
        while i < len(code):
            if code[i] == '(':
                depth += 1
            elif code[i] == ')':
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            i += 1
        semi = code.find(';', i)
        # The column list plus any WHERE predicate, and nothing past the
        # statement's own semicolon.
        out.append((m.group(1), code[m.end():semi if semi >= 0 else len(code)]))
    return out


indexes_on: dict[str, set[str]] = {}
declared_immutable: set[str] = set()
first_seen: dict[str, str] = {}
replacements: list[tuple[str, str, str]] = []   # (stem, function, raw sql)

for path in sorted(MIGRATIONS.glob('*.sql')):
    raw = path.read_text(encoding='utf-8')
    code = strip_comments(raw)
    for index_name, built_from in index_definitions(code):
        # The function an index is BUILT ON, not the table it is on.
        for fn in BUILT_ON.findall(built_from):
            indexes_on.setdefault(fn.lower(), set()).add(index_name.lower())
    for fn, body in function_bodies(code).items():
        signature = code[:code.find(body)] if body in code else ''
        if fn in first_seen and first_seen[fn] != path.stem:
            replacements.append((path.stem, fn, code))
        else:
            first_seen.setdefault(fn, path.stem)
    for m in re.finditer(
            r'CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.(\w+)\s*\('
            r'(?:.|\n){0,400}?\bIMMUTABLE\b', code, re.I):
        declared_immutable.add(m.group(1).lower())

for stem, fn, code in replacements:
    needed = indexes_on.get(fn, set())
    if not needed or fn not in declared_immutable:
        continue
    missing = sorted(i for i in needed
                     if not re.search(rf'REINDEX\b[^;]*\b{re.escape(i)}\b',
                                      code, re.I))
    if missing:
        faults.append(
            f'{stem} replaces the IMMUTABLE function `{fn}`, and '
            f'{", ".join(missing)} is built on it. PostgreSQL believes '
            f'IMMUTABLE: the index keeps the values computed under the old body '
            f'and is not rebuilt. An index scan would then search new keys '
            f'among old ones and find nothing, while a sequential scan returned '
            f'the right answer — the same query right or wrong by plan. '
            f'REINDEX it in this migration.')
if not any('IMMUTABLE function' in f for f in faults):
    indexed = {f: i for f, i in indexes_on.items() if f in declared_immutable}
    proved.append(
        f'{len(indexed)} indexed IMMUTABLE function(s) '
        f'({", ".join(sorted(indexed)) or "none"}) — every replacement rebuilds '
        f'the indexes built on it')

if faults:
    print('FAIL: a place name does not resolve to the place.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-95.')
    sys.exit(1)

print('OK: a ward resolves to itself, and an indexed function is rebuilt when '
      'replaced.')
for item in proved:
    print(f'  * {item}')
print(f'  * geo_key applied from the {len(steps)} pattern(s) in the migration '
      f'itself, not reimplemented here')
