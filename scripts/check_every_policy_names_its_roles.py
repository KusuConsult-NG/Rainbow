#!/usr/bin/env python3
"""Every CREATE POLICY must say WHO. A missing TO clause means TO PUBLIC.

    python3 scripts/check_every_policy_names_its_roles.py

## What went wrong, twice

A production policy query came back with two rows:

    alerts_select_geo_lga_scoped    | alerts    | SELECT
    telemetry_select_geo_lga_scoped | telemetry | SELECT

Both are created by `20260725000000_v6_geo_lga_scoping_staging.sql`, twelve
lines apart. The telemetry one is written `TO authenticated`. The alerts one
was written with no TO clause at all — and PostgreSQL records such a policy as
**TO PUBLIC**, and PUBLIC includes `anon`.

The telemetry one had already been found on a live database, where it sat as
the single policy reaching PUBLIC for weeks, and repaired by
`20261016000000_telemetry_policy_is_not_public.sql`. That fix put a comment in
the v6 file explaining that `TO authenticated` is not decoration. The policy
twelve lines ABOVE that comment, on the incident table — reporter names, phone
numbers, locations — kept the defect. Nobody looked at the sibling.

Three layers missed it, and they are structural rather than careless:

  * `20260813000000_rls_least_privilege.sql` drops prior policies BY EXACT
    NAME, 98 of them, and cannot name a policy from a file written later.
  * `20260725…_staging.sql` is STAGING_ONLY, so it is not in the production
    paste — yet production carries its policies, because that era was applied
    by hand. A file excluded from the paste still shaped the database.
  * `verify_rls_migration.sh` asserts that no policy reaches anon or public at
    the END of the full replay, and passes, because a later migration drops
    this policy on its way to a narrower one. The end state is clean.
    Production sits in the MIDDLE, where it exists and the drop has not run.

A check at one point in the history cannot answer a question about another
point. This one asks nothing about history: a policy that does not name its
roles is wrong in the file, on the day it is written, whatever is applied
before or after it.

## What this checks

Every `CREATE POLICY` in `supabase/` and `scripts/` names `TO`. The clause may
say anything — `TO authenticated`, `TO service_role`, even `TO public` — the
rule is that it is WRITTEN, so the intent is visible to a reader and to a
reviewer. Silence is the defect, because silence means PUBLIC and reads like
nothing.

## The historical era

43 policies in the v2–v6 and phase1 files predate this rule, and those files
are deliberately preserved as history: `20261017000000` is named "the hand
applied era is in the history" and exists to record what production was given
by hand. They are listed below, exactly, by file and policy name. The list is a
frozen inventory, not a pattern — adding a NEW policy to one of those files
fails this check, and so does renaming one.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# The v2–v6 and phase1 era, as it stands. Every entry is (file, policy): a
# frozen inventory so a new policy in an old file is still caught.
# `20260813000000_rls_least_privilege.sql` drops all of these by name and
# replaces them with policies that do name their roles.
HISTORICAL = {
    ('supabase/migrations/20260721000000_v2_agency_tables.sql', p) for p in (
        'alerts_insert_authenticated', 'alerts_read_authenticated',
        'alerts_update_authenticated', 'chat_insert_authenticated',
        'chat_read_authenticated', 'profiles_read_all', 'profiles_write_own',
        'sysalerts_read_authenticated', 'sysalerts_write_hq',
        'telemetry_read_authenticated', 'telemetry_write_own',
    )
} | {
    ('supabase/migrations/20260722000000_v3_telemetry_geofence.sql', p) for p in (
        'agency_notifications_insert', 'agency_notifications_read',
    )
} | {
    ('supabase/migrations/20260723000000_v4_mesh_broadcast.sql', p) for p in (
        'agency_deployments_read', 'agency_deployments_write',
        'agency_personnel_read', 'agency_personnel_write',
        'agency_reports_read', 'agency_reports_write',
    )
} | {
    ('supabase/migrations/20260724000000_v5_rls_security.sql', p) for p in (
        'alerts_delete_hq_only', 'alerts_insert_authenticated',
        'alerts_select_own', 'alerts_select_responders',
        'alerts_update_responders_only', 'chat_insert_authenticated',
        'chat_select_own_alerts', 'chat_select_responders',
        'profiles_delete_hq', 'profiles_insert_own', 'profiles_select_own',
        'profiles_select_responders', 'profiles_update_own',
        'system_alerts_manage_hq', 'system_alerts_select_all_authenticated',
        'telemetry_select_responders', 'telemetry_upsert_own',
    )
} | {
    ('supabase/migrations/phase1_foundation.sql', p) for p in (
        'chat_insert', 'chat_read', 'safe_zones_read', 'telemetry_own_upsert',
        'telemetry_read_all', 'uninstall_insert', 'uninstall_read',
    )
}

# `supabase/rainbow_full_migration.sql` is a hand-assembled bundle that carries
# the whole history inline, and the generated bundles under scripts/ carry
# whatever the migrations say. Checking the SOURCE is what matters; a bundle
# cannot be fixed without fixing the file it was built from.
GENERATED = (
    'supabase/rainbow_full_migration.sql',
    'scripts/apply_all_migrations.sql',
    'scripts/bootstrap_staging.sql',
    'scripts/rls_production_dryrun.sql',
)

# CREATE POLICY <name> ON <table> [AS …] [FOR …] [TO …] USING/WITH CHECK
POLICY = re.compile(
    r'CREATE\s+POLICY\s+"?([A-Za-z_][\w]*)"?\s+ON\s+([\w.]+)(.*?)'
    r'(?=\bUSING\b|\bWITH\s+CHECK\b|;)', re.S | re.I)
NAMES_ROLES = re.compile(r'\bTO\s+("?[A-Za-z_][\w]*"?)', re.I)
LINE_COMMENT = re.compile(r'--[^\n]*')


def sources() -> list[Path]:
    seen: list[Path] = []
    for base in ('supabase', 'scripts'):
        for path in sorted((REPO / base).rglob('*.sql')):
            rel = str(path.relative_to(REPO))
            if rel.startswith('scripts/apply_in_parts/') or rel in GENERATED:
                continue
            seen.append(path)
    return seen


failures: list[str] = []
checked = 0
grandfathered = 0
probes = 0

for path in sources():
    rel = str(path.relative_to(REPO))
    # Comments are blanked, not removed: this file's own prose quotes the
    # defective statement, and several migrations quote it to explain it.
    text = LINE_COMMENT.sub('', path.read_text(encoding='utf-8'))
    for match in POLICY.finditer(text):
        name, table, head = match.group(1), match.group(2), match.group(3)
        checked += 1
        if NAMES_ROLES.search(head):
            continue
        if (rel, name) in HISTORICAL:
            grandfathered += 1
            continue
        # A PLANTED PROBE. `policy_roles_behaviour_test.sql` creates a policy
        # with no TO clause on purpose, to prove that its own sweep can detect
        # one — the earlier version of that claim passed every run for weeks
        # while a TO PUBLIC policy sat on telemetry, so the assertion has to be
        # watched failing. Narrow on purpose: the name must be `zz_…` and the
        # same file must DROP it, so a probe left behind on a real database
        # still fails this check.
        if (name.startswith('zz_')
                and re.search(rf'DROP\s+POLICY\s+(IF\s+EXISTS\s+)?"?{re.escape(name)}"?',
                              text, re.I)):
            probes += 1
            continue
        line = text[:match.start()].count('\n') + 1
        failures.append(
            f'{rel}:{line} — `CREATE POLICY "{name}" ON {table}` names no '
            'roles. PostgreSQL records a policy with no TO clause as TO '
            'PUBLIC, and PUBLIC includes `anon`: the policy is reachable by '
            'anyone holding the anonymous key, and the only thing standing in '
            'the way is a table-level REVOKE one GRANT could undo. Write the '
            'clause — `TO authenticated` almost always, `TO service_role` for '
            'a server-only path — so a reader can see who it is for. This '
            'exact mistake sat on production twice: '
            'telemetry_select_geo_lga_scoped for weeks, and '
            'alerts_select_geo_lga_scoped beside it, unnoticed, with the '
            'explanation already written twelve lines away.')

if failures:
    print('A policy that does not say who it is for:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_every_policy_names_its_roles.py for why this '
          'matters.')
    sys.exit(1)

still_untyped = {
    (str(p.relative_to(REPO)), m.group(1))
    for p in sources()
    for m in POLICY.finditer(LINE_COMMENT.sub('', p.read_text(encoding='utf-8')))
    if not NAMES_ROLES.search(m.group(3))
}
missing = sorted(HISTORICAL - still_untyped)
if missing:
    print('The historical inventory names policies that are no longer there:\n')
    for rel, name in missing:
        print(f'  * {rel} no longer creates `{name}` without a TO clause — '
              'remove it from HISTORICAL so the list keeps meaning what it '
              'says.\n')
    sys.exit(1)

print('Every policy says who it is for:')
print(f'  * {checked} CREATE POLICY statements read from supabase/ and '
      f'scripts/')
print(f'  * {checked - grandfathered - probes} name their roles; '
      f'{grandfathered} are the v2–v6 and phase1 era,\n    listed exactly, '
      'which 20260813000000_rls_least_privilege.sql drops by name')
print(f'  * {probes} planted probe(s), each dropped in the same file, which is '
      'how a sweep\n    for this defect is proven able to detect one')
