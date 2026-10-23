#!/usr/bin/env python3
"""The app and the database must agree on who is a commander.

    python3 scripts/check_one_command_vocabulary.py

## What went wrong

The production project's 22 staff accounts carry a vocabulary this repository
never had — `STATE_COMMANDER`, `LGA_COMMANDER`, `WARD_COMMANDER`,
`POLLING_UNIT_OFFICER`. It took two findings to work through what that broke,
in two different layers:

**T-85, the app.** `auth_provider.dart` chose a rung by substring test, so
`STATE_COMMANDER` matched none of HQ/LGA/WARD/UNIT/POLLING and every HQ duty
officer was silently shown a polling unit's board.

**T-90, the database.** `is_command()` and `commands_whole_state()` are
exact-match lists. Exactly two of those 22 accounts satisfied `is_command()`, so
every other commander was refused by every policy gated on it — posting an
advisory, publishing a shelter, the whole agency portal, acknowledging a SIM
swap. And `commands_whole_state()` is why an HQ duty officer's incident scope
fell back to one polling unit.

Both were fixed by teaching each layer the second spelling. Which leaves the
thing that caused it: **two lists, in two languages, that have to agree and
nothing checked.**

## What this checks

Every role the APP treats as a command rung is recognised by the DATABASE:

1. a role mapping to `ResponderTier.hq` in `staffRoleTiers` must satisfy both
   `is_command()` and `commands_whole_state()`;
2. a role mapping to `ResponderTier.lga` must satisfy `is_command()`;
3. a role mapping to `ward`, `pu` or `unknown` must satisfy NEITHER — so a
   later widening cannot quietly move a ward officer up the chain.

The database is allowed names the app does not have (`HQ_OFFICER`, `ADMIN` are
not app roles). The direction that matters is the other one: a rung the app
hands somebody must be a rung the database honours.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DART = REPO / 'lib/providers/auth_provider.dart'
MIGRATIONS = REPO / 'supabase/migrations'

# AND THE CONSOLE, WHICH THIS CHECK COULD NOT SEE.
#
# This read the Dart map and two SQL functions, and passed — while the console
# carried TEN separate exact-match role lists of its own, none of which knew the
# second vocabulary, and `escalation_push_targets()` carried four more in SQL.
# So T-85 fixed the app, T-90 fixed two SQL predicates, this gate confirmed
# those two agreed, and on the deployment a ward escalation was still addressed
# to nobody.
#
# The subject of "one vocabulary" is every place that maps a role to a rung.
# Reading two of five is the same mistake as every other gap this audit has
# found. T-97.
CONSOLE = REPO / 'hq-dashboard-next/src'
CONSOLE_MAP = CONSOLE / 'lib/command-roles.ts'

# The rung names each language uses for the same four rungs.
TIER_OF_DART = {'hq': 'HQ', 'lga': 'LGA', 'ward': 'WARD', 'pu': 'UNIT'}

# ── the app's vocabulary ───────────────────────────────────────────────────
dart = DART.read_text(encoding='utf-8')
block = re.search(r'staffRoleTiers\s*=\s*<String,\s*ResponderTier>\{(.*?)\n\};',
                  dart, re.S)
if block is None:
    print('lib/providers/auth_provider.dart no longer declares staffRoleTiers.')
    print('That is the app half of the one vocabulary. See T-85 and T-90.')
    sys.exit(1)
app_roles = {
    m.group(1).upper(): m.group(2)
    for m in re.finditer(r"'([A-Za-z_]+)':\s*ResponderTier\.(\w+)", block.group(1))
}
if not app_roles:
    print('staffRoleTiers is empty — nothing maps a role to a rung.')
    sys.exit(1)

# ── the database's, from the LAST migration that defines each function ────
def sql_role_list(fn: str) -> set[str] | None:
    """The IN(...) list of the newest definition of `fn`."""
    found = None
    for path in sorted(MIGRATIONS.glob('*.sql')):
        text = path.read_text(encoding='utf-8', errors='replace')
        for m in re.finditer(
                rf'CREATE OR REPLACE FUNCTION public\.{fn}\(\)(.*?)\$\$;',
                text, re.S):
            body = m.group(1)
            # strip SQL comments so a commented-out name is not a permission
            body = re.sub(r'--[^\n]*', '', body)
            names = re.search(r'\bIN\s*\((.*?)\)', body, re.S)
            if names:
                found = {n.upper() for n in re.findall(r"'([A-Za-z_]+)'",
                                                       names.group(1))}
    return found


is_command = sql_role_list('is_command')
whole_state = sql_role_list('commands_whole_state')

# ── the console's, from the one module it is allowed to live in ────────────
def ts_role_map() -> dict[str, str | None] | None:
    """{ROLE: 'HQ'|'LGA'|'WARD'|'UNIT'|None} from STAFF_ROLE_TIERS."""
    if not CONSOLE_MAP.is_file():
        return None
    text = CONSOLE_MAP.read_text(encoding='utf-8')
    block = re.search(r'STAFF_ROLE_TIERS[^=]*=\s*\{(.*?)\n\};', text, re.S)
    if block is None:
        return None
    body = re.sub(r'//[^\n]*', '', block.group(1))
    out: dict[str, str | None] = {}
    for m in re.finditer(r'(\w+):\s*(?:\'(\w+)\'|(null))', body):
        out[m.group(1).upper()] = m.group(2).upper() if m.group(2) else None
    return out or None


def sql_tier_lists() -> dict[str, set[str]] | None:
    """{'HQ': {...}, ...} from the newest roles_for_tier()."""
    found = None
    for path in sorted(MIGRATIONS.glob('*.sql')):
        text = path.read_text(encoding='utf-8', errors='replace')
        for m in re.finditer(
                r'CREATE OR REPLACE FUNCTION public\.roles_for_tier\([^)]*\)'
                r'(.*?)\$\$;', text, re.S):
            body = re.sub(r'--[^\n]*', '', m.group(1))
            lists: dict[str, set[str]] = {}
            for w in re.finditer(
                    r"WHEN\s*'(\w+)'\s*THEN\s*ARRAY\[(.*?)\]", body, re.S):
                lists[w.group(1).upper()] = {
                    n.upper() for n in re.findall(r"'([A-Za-z_]+)'", w.group(2))}
            if lists:
                found = lists
    return found


# Any role literal outside the one module is a list waiting to go stale. The
# badge prefixes ('HQ-', 'PU-') are not role names and are not matched.
STRAY = re.compile(
    r"['\"](?:HQ_COMMAND|HQ_OFFICER|LGA_COMMAND|LGA_COMMANDER|WARD_COMMAND"
    r"|WARD_COMMANDER|UNIT_COMMAND|POLLING_UNIT_OFFICER|POLLING_OFFICER"
    r"|STATE_COMMANDER|LGA_OFFICER|WARD_OFFICER)['\"]")
# Files allowed to name a role: the one map, the account-creation form whose
# job is to offer the names, and anything under a test.
STRAY_EXEMPT = re.compile(
    r'command-roles\.ts$|AdminDirectory\.tsx$|\.test\.(ts|tsx)$'
    r'|/__fixtures__/|provision/route\.ts$')

problems: list[str] = []
if is_command is None:
    problems.append('no migration defines is_command() with a role list')
if whole_state is None:
    problems.append('no migration defines commands_whole_state() with a role list')

console_roles = ts_role_map()
tier_lists = sql_tier_lists()
if console_roles is None:
    problems.append(
        'hq-dashboard-next/src/lib/command-roles.ts does not declare '
        'STAFF_ROLE_TIERS. That is the console half of the one vocabulary, and '
        'without it the console goes back to ten exact-match lists.')
if tier_lists is None:
    problems.append(
        'no migration defines roles_for_tier() with per-tier role lists. '
        'escalation_push_targets() carried its own four, and a ward escalation '
        'on the deployment was addressed to nobody.')

# ── every rung the app knows must be reachable in the other two languages ──
if console_roles is not None and tier_lists is not None:
    for role, dart_tier in sorted(app_roles.items()):
        want = TIER_OF_DART.get(dart_tier)
        if want is None:
            continue    # deliberately outside the chain
        if console_roles.get(role) != want:
            problems.append(
                f'the app puts {role} at the {want} rung and the console says '
                f'{console_roles.get(role) or "nothing"}. The console decides '
                f'what that officer is shown and which API routes accept them.')
        if role not in tier_lists.get(want, set()):
            problems.append(
                f'the app puts {role} at the {want} rung and '
                f'roles_for_tier({want!r}) does not list it, so an automatic '
                f'escalation to that rung is addressed to everybody EXCEPT '
                f'them. On an empty list deliverTierEscalation throws "no '
                f'reachable officer at that tier" and the notice is never '
                f'delivered to anybody.')

# ── and the two tier->roles lists must agree with each other ───────────────
if console_roles is not None and tier_lists is not None:
    for tier in sorted(tier_lists):
        from_ts = {r for r, t in console_roles.items() if t == tier}
        from_sql = tier_lists[tier]
        if from_ts != from_sql:
            only_sql = sorted(from_sql - from_ts)
            only_ts = sorted(from_ts - from_sql)
            problems.append(
                f'the {tier} rung is held by {sorted(from_sql)} in SQL and '
                f'{sorted(from_ts)} in the console'
                + (f'; only SQL has {only_sql}' if only_sql else '')
                + (f'; only the console has {only_ts}' if only_ts else '')
                + '. There are two drainers and they address different people.')

# ── no stray list anywhere else in the console ─────────────────────────────
for path in sorted(CONSOLE.rglob('*.ts')) + sorted(CONSOLE.rglob('*.tsx')):
    rel = str(path.relative_to(REPO))
    if STRAY_EXEMPT.search(rel):
        continue
    text = path.read_text(encoding='utf-8', errors='replace')
    # BLANKED, NOT DELETED. Removing a block comment removes its newlines and
    # shifts every line number after it, so the first run of this check sent me
    # to a colour map and a doc comment instead of the three real sites. The
    # repo's own strip_noise does it this way for exactly this reason.
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'/\*.*?\*/',
                  lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text, flags=re.S)
    for m in STRAY.finditer(text):
        problems.append(
            f'{rel}:{text.count(chr(10), 0, m.start()) + 1} names the role '
            f'{m.group(0)} directly. Ten lists like this is what made a '
            f'STATE_COMMANDER invisible to the console; ask '
            f'lib/command-roles.ts instead, which derives every list from the '
            f'one role-to-rung map.')

if not problems:
    for role, tier in sorted(app_roles.items()):
        in_cmd = role in is_command
        in_whole = role in whole_state
        if tier == 'hq':
            if not in_cmd:
                problems.append(
                    f'{role} is an HQ rung in the app and is_command() does not '
                    'know it, so that commander cannot post an advisory, '
                    'publish a shelter, or use the agency portal')
            if not in_whole:
                problems.append(
                    f'{role} is an HQ rung in the app and commands_whole_state() '
                    'does not know it, so their incident scope falls back to '
                    'their own posting')
        elif tier == 'lga':
            if not in_cmd:
                problems.append(
                    f'{role} is an LGA rung in the app and is_command() does '
                    'not know it')
            if in_whole:
                problems.append(
                    f'{role} is an LGA rung and commands_whole_state() claims '
                    'it commands the state')
        else:
            if in_cmd:
                problems.append(
                    f'{role} is {tier} in the app and is_command() accepts it — '
                    'that moves somebody up the chain')
            if in_whole:
                problems.append(
                    f'{role} is {tier} in the app and commands_whole_state() '
                    'accepts it')

if problems:
    print('The app and the database disagree about who commands:\n')
    for p in problems:
        print(f'  * {p}')
    print()
    print('One vocabulary, THREE languages. staffRoleTiers in')
    print('lib/providers/auth_provider.dart; is_command(),')
    print('commands_whole_state() and roles_for_tier() in')
    print('supabase/migrations/; STAFF_ROLE_TIERS in')
    print('hq-dashboard-next/src/lib/command-roles.ts. All three carry every')
    print('spelling a deployment uses, and every list is DERIVED from the map')
    print('rather than written out again — ten lists written out again is how')
    print('a ward escalation came to be addressed to nobody.')
    print('See E2E_AUDIT_REPORT.md T-85, T-90, T-97.')
    sys.exit(1)

hq = sorted(r for r, t in app_roles.items() if t == 'hq')
lga = sorted(r for r, t in app_roles.items() if t == 'lga')
print('OK: the app and the database agree about who commands.')
print(f'  * {len(app_roles)} role(s) in staffRoleTiers, across both vocabularies')
print(f'  * HQ rung ({", ".join(hq)}) satisfies is_command() and '
      'commands_whole_state()')
print(f'  * LGA rung ({", ".join(lga)}) satisfies is_command() only')
print('  * every ward, polling-unit and untiered role satisfies neither')
# Counted, not merely asserted: a check whose subject came back empty prints a
# reassuring line. That happened in this audit ("0 indexed IMMUTABLE
# function(s)") and the count is what gave it away.
chain = {r: t for r, t in app_roles.items() if TIER_OF_DART.get(t)}
print(f'  * {len(chain)} chain role(s) are at the same rung in the console map '
      f'({len(console_roles or {})} roles) as in the app')
print('  * roles_for_tier() and the console agree per rung: '
      + '; '.join(f'{tier}={len(roles)}'
                  for tier, roles in sorted((tier_lists or {}).items())))
scanned = len(list(CONSOLE.rglob('*.ts'))) + len(list(CONSOLE.rglob('*.tsx')))
print(f'  * {scanned} console file(s) read, and none names a staff role '
      f'outside lib/command-roles.ts')
