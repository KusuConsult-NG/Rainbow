#!/usr/bin/env python3
"""An outside agency sees what was handed to them, on every surface.

    python3 scripts/check_alert_audience_agrees.py

## What went wrong

Six agencies send liaison officers to this system. `20261003000000` and
`20261006000000` made the database say exactly what they may see:

    -- alert_is_ours()
    -- An outside agency: only what was handed to them.
    OR (public.is_liaison()
        AND upper(COALESCE(p_alert.escalated_to_agency, '')) = public.liaison_agency());

The word "liaison" did not appear anywhere in `lib/`. The handset's feed filter
— a `.where()` inside `alertsStreamProvider` — had no branch that could match
one, so it fell through to the place rules and compared each incident's location
against the liaison's OWN POSTING. The Army liaison in the fixtures is posted to
MANGU; the incident escalated to the Army is in JOS NORTH; their feed was empty.
HQ's console shows the handover as done and `/api/notify-agency` reports it
sent, while the device the officer carries shows nothing. T-28 was "escalating
an incident to the Police reached nobody, by three paths at once"; this was a
fourth.

No harness run caught it because against the local stand-in it fails the OTHER
way: `fake_supabase.js` applies no RLS, so the Police liaison — posted where the
fixture incidents are — was admitted by the place rules and shown incidents
never handed to the Police. Empty against production, wrong against the
stand-in, green in both.

And the rule had no test of its own: four test files call
`alertsStreamProvider.overrideWith(...)`, which replaces the closure the rule
lived in. It is `lib/services/alert_audience.dart` now, tested, the way
`broadcast_targeting.dart` and `assignable_responders.dart` already were.

## The asymmetry this check protects

RLS decides access. The client filter decides what is worth putting in front of
somebody, so a polling-unit officer is not handed the whole state. It may be
MORE permissive than RLS harmlessly — the rows never arrive — but it must never
be STRICTER, because anything it drops that the database deliberately granted is
an emergency somebody was meant to see.

## What this checks

1. `alert_is_ours()` still scopes a liaison to `escalated_to_agency`.
2. `is_liaison()` and `liaison_agency()` still derive the agency from the ROLE,
   not from `profiles.agency`, which is a decorative badge (T-28).
3. The app has a liaison branch that reads `escalated_to_agency`, and it
   RETURNS rather than falling through to the place rules — falling through is
   what the defect was.
4. That branch sits before the place rules, for the same reason.
5. The app derives the agency from a `_LIAISON` role suffix, as both the SQL
   and the console's `agencyOf()` do.
6. `alertsStreamProvider` does not carry its own copy of the rule.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SQL = REPO / 'supabase' / 'migrations' / '20261006000000_alerts_scoped_to_posting.sql'
LIAISON_SQL = REPO / 'supabase' / 'migrations' / '20261003000000_liaisons_are_not_staff.sql'
DART = REPO / 'lib' / 'services' / 'alert_audience.dart'
PROVIDER = REPO / 'lib' / 'features' / 'agent' / 'agent_dashboard_screen.dart'
CONSOLE = REPO / 'hq-dashboard-next' / 'src' / 'lib' / 'console-access.ts'

failures: list[str] = []


def fail(message: str) -> None:
    failures.append(message)


def strip_dart_comments(text: str) -> str:
    """Blanked, not removed, so line numbers survive."""
    pattern = re.compile(r'/\*.*?\*/|///[^\n]*|//[^\n]*', re.S)
    return pattern.sub(lambda m: re.sub(r'[^\n]', ' ', m.group(0)), text)


for path in (SQL, LIAISON_SQL, DART, PROVIDER, CONSOLE):
    if not path.exists():
        sys.exit(f'{path.relative_to(REPO)} is missing')

# ── 1. The database's own rule ──
sql = SQL.read_text()
clause = re.search(
    r'is_liaison\(\)\s*(?:--[^\n]*\n\s*)*AND\s+upper\(\s*COALESCE\(\s*'
    r'p_alert\.escalated_to_agency\s*,\s*\'\'\s*\)\s*\)\s*'
    r'(?:--[^\n]*\n\s*)*=\s*(?:--[^\n]*\n\s*)*public\.liaison_agency\(\)',
    sql, re.S)
if not clause:
    fail('`alert_is_ours()` no longer scopes a liaison to '
         '`escalated_to_agency = liaison_agency()`. That clause is the only '
         'thing that gives an outside agency any incident at all, and the only '
         'thing that stops it giving them every incident in the state.')

# ── 1b. The other two grants the handset must not be stricter than ──
if not re.search(
        r"WHEN\s*\(\s*SELECT\s+lga\s+FROM\s+it\s*\)\s+IS\s+NULL\s+THEN\s+true",
        sql, re.I):
    fail('`alert_in_my_area()` no longer treats an incident with no LGA as '
         'unlocated and visible to all staff. Its own note says why: "an '
         'emergency nobody can see is worse than one seen too widely."')

delegated = re.search(
    r'CREATE OR REPLACE FUNCTION public\.alert_delegated_to_my_lga\(.*?\$\$;',
    sql, re.S)
if not delegated:
    fail('`alert_delegated_to_my_lga()` is gone. HQ hands an incident down by '
         'naming a target LGA, and that function is the only thing that gives '
         'it to that LGA when the incident sits outside their boundary.')
else:
    d = delegated.group(0)
    if 'to_lga' not in d:
        fail('`alert_delegated_to_my_lga()` no longer reads `to_lga` from the '
             'escalation log.')
    if 'jsonb_array_length' not in d:
        fail('`alert_delegated_to_my_lga()` no longer reads the LAST escalation '
             'entry. The log is append-only, so an earlier handover has been '
             'superseded and reading any other entry re-grants it.')

# ── 2. The agency comes from the role ──
liaison_sql = LIAISON_SQL.read_text()
if not re.search(r"LIKE\s+'%\\_LIAISON'", liaison_sql):
    fail('`is_liaison()` no longer recognises a role by its `_LIAISON` suffix. '
         'All three definitions of "which agency is this account" key on that '
         'suffix — here, `agencyOfRole()` in Dart and `agencyOf()` in the '
         'console — because `profiles.agency` is a decorative badge (T-28).')
if 'profiles.agency' in liaison_sql.replace('-- ', ''):
    # Only a worry if it is being READ as the answer; a comment is fine.
    bodies = re.findall(r'FUNCTION public\.liaison_agency\(\).*?\$\$;', liaison_sql, re.S)
    if any('profiles.agency' in b for b in bodies):
        fail('`liaison_agency()` reads `profiles.agency`. That column is '
             'self-writable decoration (T-28); the role is what RLS keys on.')

# ── 3, 4, 5. The app's rule ──
dart = strip_dart_comments(DART.read_text())

if "endsWith('_LIAISON')" not in dart:
    fail('`alert_audience.dart` no longer derives the agency from a `_LIAISON` '
         'role suffix, so it and the SQL would disagree about who is a liaison.')

reaches = re.search(r'bool alertReaches\(.*?\n\}', dart, re.S)
if not reaches:
    fail('`alertReaches()` is gone from `alert_audience.dart`, so this check '
         'cannot see what the handset shows.')
else:
    body = reaches.group(0)
    branch = re.search(
        r'if\s*\(\s*officer\.isLiaison\s*\)\s*\{(?P<inner>.*?)\n  \}', body, re.S)
    if not branch:
        fail('`alertReaches()` has no `if (officer.isLiaison)` branch. Without '
             'one a liaison falls through to the place rules, which compare '
             'the incident\'s location to the liaison\'s own posting — so the '
             'incidents handed to their agency are the ones they do not see.')
    else:
        inner = branch.group('inner')
        if 'escalated_to_agency' not in inner:
            fail('the liaison branch of `alertReaches()` does not read '
                 '`escalated_to_agency`, which is the only column that says '
                 'which incidents were handed to an agency.')
        # The branch must be EXHAUSTIVE, not merely contain a return: a
        # `if (handed == ours) return true;` leaves every other row falling
        # through to the place rules, which is the defect with one case fixed.
        # So the branch's LAST statement has to be the return.
        last = next((line.strip() for line in reversed(inner.splitlines())
                     if line.strip()), '')
        if not re.match(r'return\b', last):
            fail('the liaison branch of `alertReaches()` ends with '
                 f'`{last[:60]}` rather than a `return`, so a row it does not '
                 'match falls through to the place rules. That is the defect: '
                 'it is how an incident handed to the Army but outside the Army '
                 'liaison\'s posting was dropped, and how one inside their '
                 'posting that was handed to nobody got in.')

        # 4. Before the place rules.
        liaison_at = body.index('officer.isLiaison')
        place = re.search(r'sameGeo\(', body)
        if place and place.start() < liaison_at:
            fail('the place rules in `alertReaches()` run before the liaison '
                 'branch. A liaison must be answered by what was handed to '
                 'their agency, not by where they are based.')

    # ── The two other grants RLS makes that this filter must honour ──
    if not re.search(r'if\s*\(\s*alertLga\s*==\s*null\s*\)\s*return true\s*;', body):
        fail('`alertReaches()` does not treat an incident with no LGA as '
             'unlocated. `alert_in_my_area()` grants it to all staff on the '
             'LGA alone; requiring the ward and PU to be absent as well is '
             'stricter than RLS, and stricter is the direction that loses '
             'emergencies.')
    if 'delegatedToLga(' not in body:
        fail('`alertReaches()` never calls `delegatedToLga()`, so an incident '
             'HQ handed down to an LGA by name does not reach that LGA unless '
             'it happens to sit inside their boundary. RLS grants it through '
             '`alert_delegated_to_my_lga()`, and the filter this replaced '
             'claimed it in a comment — "or escalated to LGA" — over code that '
             'read only `geo_lga`.')
    else:
        delegate_at = body.index('delegatedToLga(')
        role_place = re.search(r"officer\.role\.contains\('(?:LGA|WARD)'\)", body)
        if role_place and role_place.start() < delegate_at:
            fail('`alertReaches()` tests the officer\'s own posting before the '
                 'delegation. An incident handed to their LGA from outside it '
                 'would be refused by the posting rule first.')

if 'delegatedLga' in open(DART).read():
    dart_last = re.search(r'String\? delegatedLga\(.*?\n\}', dart, re.S)
    if dart_last and 'log.last' not in dart_last.group(0):
        fail('`delegatedLga()` does not read the LAST escalation entry, as '
             '`alert_delegated_to_my_lga()` does. The log is append-only: an '
             'earlier handover has been superseded.')

# ── 6. One owner ──
provider = strip_dart_comments(PROVIDER.read_text())
stream = re.search(
    r'final alertsStreamProvider = StreamProvider<AlertsFeed>\(\(ref\)\s*\{.*?\n\}\);',
    provider, re.S)
if not stream:
    fail('`alertsStreamProvider` is gone from the dashboard, so this check '
         'cannot see whether it reimplements the rule.')
else:
    closure = stream.group(0)
    if 'alertReaches' not in closure:
        fail('`alertsStreamProvider` no longer calls `alertReaches()`. The rule '
             'was a `.where()` in this closure, which every test that touches '
             'the feed overrides — so it had no test of its own.')
    for token in ('sameGeo(', 'geo_ward', 'geo_pu', 'escalated_to_agency'):
        if token in closure:
            fail(f'`alertsStreamProvider` mentions `{token}`, so it is deciding '
                 'the audience again rather than asking '
                 '`alert_audience.dart`. One owner, or the copy drifts.')

# ── 7. The SECOND filter, which is the one that actually hid the incident ──
#
# The dashboard filters again at build time, and that pass applies
# `tierCanSee()` — Operation Rainbow's own command ladder. A liaison has no rung
# on it, so an incident handed to their agency, which always has a Rainbow tier
# owning it, ranked above them and was dropped after the stream filter had
# delivered it. One fix in one filter looked complete and was not.
build = re.search(
    r'final filteredAlerts = allDocs\.where\(\(alert\)\s*\{.*?\n    \}\)',
    provider, re.S)
if not build:
    fail('the dashboard\'s `filteredAlerts` pass is gone, so this check cannot '
         'see whether the second filter answers a liaison.')
else:
    pass_body = build.group(0)
    if 'isLiaison' not in pass_body:
        fail('`filteredAlerts` does not answer a liaison. It applies '
             '`tierCanSee()`, which is Operation Rainbow\'s internal command '
             'ladder — a liaison has no rung on it, so every incident that has '
             'a tier owning it outranks them, which is every incident they are '
             'ever handed. The stream filter delivering the row is not enough.')
    elif 'tierCanSee' in pass_body and \
            pass_body.index('isLiaison') > pass_body.index('tierCanSee'):
        fail('`filteredAlerts` tests `tierCanSee()` before it answers a '
             'liaison, so the command ladder refuses them first.')

# ── And the console's third definition of the same thing ──
console = CONSOLE.read_text()
if "endsWith('_LIAISON')" not in console:
    fail('`console-access.ts` no longer derives the agency from a `_LIAISON` '
         'suffix. Three surfaces answer "which agency is this account" and they '
         'have to answer it the same way.')

if failures:
    print('An outside agency would see the wrong incidents:\n')
    for message in failures:
        print(f'  * {message}\n')
    print('See scripts/check_alert_audience_agrees.py for why this matters.')
    sys.exit(1)

print('An outside agency sees what was handed to them, on every surface:')
print('  * alert_is_ours() scopes a liaison to escalated_to_agency')
print('  * alertReaches() answers a liaison from that column, before any place rule')
print('  * an unlocated incident and a delegated LGA reach whom RLS grants them to')
print('  * both of the handset\'s filters ask for the answer, not just the stream one')
print('  * SQL, Dart and the console all read the agency off the _LIAISON role')
