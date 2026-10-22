#!/usr/bin/env python3
"""Every migration must be applied by the replay that proves migrations work.

    python3 scripts/check_the_replay_applies_every_migration.py

## What went wrong

`scripts/verify_rls_migration.sh` builds a real PostgreSQL 16 from the
migrations and asserts, among much else, that **every object an applied
migration declares exists in the schema**. The inventory it checks against is
extracted from `supabase/migrations/` by `sync_migration_inventory.py`, so it
cannot drift.

The list of migrations the replay APPLIES is a hand-written sequence of
`psql_run -f …` lines in that shell script. Nothing connected the two.

So `20261026000000_safe_zones_capacity.sql` was added, the inventory picked up
`column safe_zones.capacity` automatically, the replay never applied the file,
and CI went red with:

    column safe_zones.capacity  (20261026000000_safe_zones_capacity)
    ✗ objects declared by an applied migration are absent from the schema

Which is the check working — it noticed. What nobody noticed is that adding a
migration silently requires editing a shell script, and the only thing that
says so is a red build after the push.

Worse in the other direction: a migration left out of the replay is **never
executed against real PostgreSQL by anything**. It reaches the production paste
through `apply_all_migrations.sql`, which `verify_apply_all.sh` does run — so
syntax is covered — but none of the behavioural assertions, idempotency replays
or policy-role checks in this harness ever see it. A migration can be wrong in
a way only PostgreSQL would tell you, and arrive in production untested, with
every gate green.

## What this checks

Every file in `supabase/migrations/` is named by `verify_rls_migration.sh` —
either in one of its `psql_run -f $PGROOT/<name>.sql` lines or in the `for f in
…` loop that applies the base schema — except the v2–v5 era, which this harness
deliberately does not replay and says so at the point where it exempts them.

The exemption is listed here by name. A new migration cannot join it by
accident; somebody has to add a line to this file and say why.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MIGRATIONS = REPO / 'supabase/migrations'
REPLAY = REPO / 'scripts/verify_rls_migration.sh'

# The v2–v5 era. `20260812000000_agency_tables.sql` stands in for it, because
# production's agency tables were made BY HAND and never came from these files.
# The replay says so where it exempts them from its own object check, and it
# asserts the exemption is RECOGNISED rather than silently absent.
NOT_REPLAYED = {
    '20260721000000_v2_agency_tables',
    '20260722000000_v3_telemetry_geofence',
    '20260723000000_v4_mesh_broadcast',
    '20260724000000_v5_rls_security',
}

if not REPLAY.is_file():
    print(f'{REPLAY.relative_to(REPO)} does not exist — renamed?')
    sys.exit(1)

sh = REPLAY.read_text(encoding='utf-8')

# Both shapes the script uses to name a migration.
named = set(re.findall(r'-f\s+"?\$PGROOT/([0-9a-z_]+)\.sql', sh))
for loop in re.findall(r'for\s+f\s+in\s+([^\n;]+?)(?:;|\s+do)', sh):
    named.update(re.findall(r'[0-9a-z_]{4,}', loop))

on_disk = {p.stem for p in sorted(MIGRATIONS.glob('*.sql'))}

missing = sorted(on_disk - named - NOT_REPLAYED)
stale = sorted(NOT_REPLAYED - on_disk)

findings: list[str] = []
for name in missing:
    findings.append(
        f'{name}.sql is never applied by the replay — no behavioural '
        'assertion, no idempotency run, nothing against real PostgreSQL')
for name in stale:
    findings.append(
        f'{name} is exempted here and no longer exists — remove it from '
        'NOT_REPLAYED so the exemption cannot outlive its subject')

if findings:
    print('The RLS replay does not apply every migration:\n')
    for item in findings:
        print(f'  * {item}')
    print()
    print('Add it to scripts/verify_rls_migration.sh, applied TWICE as every')
    print('migration there is, with an assertion about what it did. A')
    print('migration no harness executes reaches production having been read')
    print('and never run. See E2E_AUDIT_REPORT.md T-79.')
    sys.exit(1)

print('OK: the replay applies every migration it is meant to.')
print(f'  * {len(on_disk)} migration(s) on disk, {len(on_disk - NOT_REPLAYED)} '
      'named by the replay')
print(f'  * {len(NOT_REPLAYED)} exempted by name: the v2–v5 era, which '
      '20260812000000 stands in for')
