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

problems: list[str] = []
if is_command is None:
    problems.append('no migration defines is_command() with a role list')
if whole_state is None:
    problems.append('no migration defines commands_whole_state() with a role list')

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
    print('One vocabulary, two languages. staffRoleTiers in')
    print('lib/providers/auth_provider.dart, and is_command() /')
    print('commands_whole_state() in supabase/migrations/. Both have to carry')
    print('every spelling a deployment uses. See E2E_AUDIT_REPORT.md T-85, T-90.')
    sys.exit(1)

hq = sorted(r for r, t in app_roles.items() if t == 'hq')
lga = sorted(r for r, t in app_roles.items() if t == 'lga')
print('OK: the app and the database agree about who commands.')
print(f'  * {len(app_roles)} role(s) in staffRoleTiers, across both vocabularies')
print(f'  * HQ rung ({", ".join(hq)}) satisfies is_command() and '
      'commands_whole_state()')
print(f'  * LGA rung ({", ".join(lga)}) satisfies is_command() only')
print('  * every ward, polling-unit and untiered role satisfies neither')
