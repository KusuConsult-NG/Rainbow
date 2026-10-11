#!/usr/bin/env python3
"""One escalation policy, meant the same way by the job and by the screen.

    python3 scripts/check_escalation_defaults_agree.py

## What went wrong

`tier_timeout_minutes()` in `20260928000000_command_chain_escalation.sql` is
the only reader of the three `app_config` escalation timeouts, and it refuses
what it cannot use:

    parsed := raw::INTEGER;                   -- '2.5' raises, and is caught
    IF parsed IS NULL OR parsed <= 0 THEN     -- falls back to the seeded value

with the reason stated: "A missing or malformed setting must not silently mean
'escalate immediately' (a timeout of 0) or 'never escalate' (NULL treated as
infinite). Both are dangerous defaults for an emergency queue."

`SystemConfig` is the only writer. It accepted anything its number input would
produce, so an operator could set the ward timeout to `0`, or to `2.5`, and it
was stored, read back, and displayed as the live policy — while the job threw
it away and used the seeded value. Two sides of one name disagreeing, which is
T-28's and T-29's signature.

It also showed its own placeholders for a key with no row and called them "not
the live policy", when the job falls back to exactly the same numbers and they
therefore ARE the effective timeout. Both halves of that rest on the two sides
agreeing about three numbers and one lower bound, and nothing was checking.

## What this checks

1. `tier_timeout_minutes()` still falls back to UNIT=2, WARD=5, LGA=10 — read
   out of the SQL, not assumed.
2. It still rejects anything `<= 0`, which is what makes the console's minimum
   of 1 the right minimum.
3. The console declares the same three numbers as `seeded`, against the same
   `app_config` keys.
4. The console's `MIN_MINUTES` is the smallest value the job honours.
5. Every migration and operator script that SEEDS those rows seeds the same
   numbers, so a fresh database starts where both sides expect.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WATCHDOG = REPO / 'supabase' / 'migrations' / '20260928000000_command_chain_escalation.sql'
CONSOLE = REPO / 'hq-dashboard-next' / 'src' / 'components' / 'SystemConfig.tsx'

# tier -> app_config key. The mapping itself lives in the SQL and is read back
# from it below; this is only the order things are reported in.
TIERS = ('UNIT', 'WARD', 'LGA')

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


for path in (WATCHDOG, CONSOLE):
    if not path.exists():
        sys.exit(f'{path.relative_to(REPO)} is missing')

sql = WATCHDOG.read_text()

# ── The job's own fallback, and the keys it reads ──
body = re.search(
    r'CREATE OR REPLACE FUNCTION public\.tier_timeout_minutes.*?\n\$\$;',
    sql, re.S)
if not body:
    sys.exit('tier_timeout_minutes() is no longer in '
             f'{WATCHDOG.relative_to(REPO)} — the job that reads the policy '
             'moved, and this check cannot see what it falls back to.')
fn = body.group(0)

sql_keys = dict(re.findall(
    r"WHEN\s+'(UNIT|WARD|LGA)'\s+THEN\s+'(escalation_timeout_\w+)'", fn))
sql_fallback = {
    tier: int(value) for tier, value in re.findall(
        r"WHEN\s+'(UNIT|WARD|LGA)'\s+THEN\s+(\d+)", fn)
}

missing_keys = [t for t in TIERS if t not in sql_keys]
missing_fallback = [t for t in TIERS if t not in sql_fallback]
if missing_keys:
    fail(f'tier_timeout_minutes() no longer maps {", ".join(missing_keys)} to an '
         'app_config key.')
if missing_fallback:
    fail(f'tier_timeout_minutes() no longer has a fallback for '
         f'{", ".join(missing_fallback)}. A tier with no fallback means a '
         'missing setting silently becomes NULL, which is "never escalate".')

# Everything below reads the console AGAINST the SQL, so if the SQL could not
# be read completely there is nothing to compare and every later message would
# be noise about the wrong side. Reported here and stopped, rather than carried
# forward — the first version carried it forward and died with a KeyError in the
# seed loop, which tells a contributor nothing.
if failures:
    print('The escalation job no longer declares the policy this check reads:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_escalation_defaults_agree.py for why this matters.')
    sys.exit(1)

# ── The lower bound it honours ──
rejects = re.search(r'parsed\s+IS\s+NULL\s+OR\s+parsed\s*<=\s*(\d+)', fn)
if not rejects:
    fail('tier_timeout_minutes() no longer rejects a non-positive timeout. The '
         'migration calls a timeout of 0 "escalate immediately" and a NULL '
         '"never escalate", and says both are dangerous defaults for an '
         'emergency queue.')
    sql_minimum = None
else:
    sql_minimum = int(rejects.group(1)) + 1

if 'raw::INTEGER' not in fn:
    fail('tier_timeout_minutes() no longer casts the stored value to INTEGER, '
         'so the console has no reason to refuse a fraction of a minute.')

# ── What the console declares ──
tsx = CONSOLE.read_text()

min_minutes = re.search(r'const\s+MIN_MINUTES\s*=\s*(\d+)\s*;', tsx)
if not min_minutes:
    fail(f'{CONSOLE.relative_to(REPO)} no longer declares MIN_MINUTES, so '
         'nothing stops it saving a timeout the job discards.')
elif sql_minimum is not None and int(min_minutes.group(1)) != sql_minimum:
    fail(f'the console accepts a minimum of {min_minutes.group(1)} minute(s) and '
         f'the job honours {sql_minimum}. An operator can save a value the job '
         'throws away, and then read it back as the policy.')

console_fields = dict(
    (key, int(seeded)) for key, seeded in re.findall(
        r"key:\s*'(escalation_timeout_\w+)'[^}]*?seeded:\s*(\d+)", tsx))

for tier in TIERS:
    key = sql_keys.get(tier)
    if key is None:
        continue
    if key not in console_fields:
        fail(f'{CONSOLE.relative_to(REPO)} declares no seeded value for `{key}`, '
             f'which the job reads for the {tier} tier.')
        continue
    if tier in sql_fallback and console_fields[key] != sql_fallback[tier]:
        fail(f'`{key}`: the console shows {console_fields[key]} when the row is '
             f'missing and the job falls back to {sql_fallback[tier]}. The '
             'screen would be stating a policy the job is not using.')

extra = sorted(set(console_fields) - set(sql_keys.values()))
if extra:
    fail(f'the console declares {", ".join(extra)}, which '
         'tier_timeout_minutes() does not read. A timeout nothing honours is a '
         'control that does nothing.')

# ── And every seed of those rows ──
SEED = re.compile(r"\(\s*'(escalation_timeout_\w+)'\s*,\s*'([^']*)'")
for path in sorted(list((REPO / 'supabase').rglob('*.sql'))
                   + list((REPO / 'scripts').rglob('*.sql'))):
    text = path.read_text()
    for key, value in SEED.findall(text):
        expected = next(
            (sql_fallback[t] for t in TIERS
             if sql_keys.get(t) == key and t in sql_fallback), None)
        if expected is None:
            continue
        try:
            seeded = int(value)
        except ValueError:
            fail(f'{path.relative_to(REPO)} seeds `{key}` as "{value}", which '
                 'the job cannot cast to INTEGER — it would fall back on a '
                 'fresh database.')
            continue
        if seeded != expected:
            fail(f'{path.relative_to(REPO)} seeds `{key}` as {seeded} and the '
                 f'job falls back to {expected}. A fresh database would not '
                 'start where either side expects.')

if failures:
    print('The escalation policy means two different things:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_escalation_defaults_agree.py for why this matters.')
    sys.exit(1)

print('One escalation policy, agreed by the job and the screen:')
for tier in TIERS:
    print(f'  * {tier}: {sql_keys[tier]} falls back to {sql_fallback[tier]} '
          'minutes on both sides')
print(f'  * the job honours >= {sql_minimum}; the console accepts >= '
      f'{min_minutes.group(1) if min_minutes else "?"}')
