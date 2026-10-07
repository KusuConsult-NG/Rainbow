#!/usr/bin/env python3
"""One list of agencies, and everything that names one is built from it.

    python3 scripts/check_one_agency_vocabulary.py

An agency code is a value in `alerts.escalated_to_agency`. Five things keyed off
it and five lists declared it, which is four too many:

    console-access.ts          AGENCY_CODES          POLICE ARMY DSS NSCDC FRSC OPSH
    AgencyPortal.tsx           AGENCIES              POLICE ARMY DSS NSCDC FRSC OPSH
    AgencyAccessManager.tsx    AGENCIES              POLICE ARMY DSS NSCDC FRSC OPSH
    notify-agency/route.ts     AGENCY_CONTACTS       POLICE ARMY DSS NSCDC FRSC OPSH
    dashboard/page.tsx         <option> literals     NPF MILITARY NSCDC DSS RAINBOW VGN

Four of the five agreed, so nothing looked wrong. The fifth is the escalation
menu — the only one an operator touches — and it had been built from
`STATE_SECURITY_AGENCIES`, a presentation list for badging Operation Rainbow's
own staff. Handing an incident to "NIGERIA POLICE FORCE (NPF TACTICAL CELL)"
therefore wrote `escalated_to_agency = 'NPF'`, and:

  * the Police liaison's portal asks for 'POLICE' and never showed it;
  * /api/notify-agency answered 400 Unknown agency, so no SMS and no webhook;
  * the operator was told "Escalation Sent — handed off to NPF Command".

FRSC and OPSH, the only two codes this deployment has contact variables for,
were not on the menu at all. Every unit test and all 79 browser assertions
passed over it, because each was written in the vocabulary of the four sides
that agreed.

A comment cannot stop that coming back. This can: `agencies.ts` owns the list,
and no other file may spell it out.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CONSOLE = REPO / 'hq-dashboard-next'
SOURCE = CONSOLE / 'src' / 'lib' / 'agencies.ts'

# Files that key off an agency code and must therefore take it from `agencies.ts`.
CONSUMERS = [
    'src/components/AgencyPortal.tsx',
    'src/components/AgencyAccessManager.tsx',
    'src/app/api/notify-agency/route.ts',
    'src/app/dashboard/page.tsx',
    'src/lib/console-access.ts',
]

# Codes the escalation menu used to offer that no agency answers to. Named so the
# failure message can say what is wrong rather than only that something is.
RETIRED = {
    'NPF': "the Police are 'POLICE' — the code the liaison role, the portal and "
           "the contact variables all use",
    'MILITARY': "'ARMY' and 'OPSH' are the two military destinations with liaison "
                "accounts; 'MILITARY' has neither a portal nor a contact number",
    'RAINBOW': 'Operation Rainbow is us — taking an incident ourselves is the HQ '
               'override, not an inter-agency handover',
    'VGN': 'no vigilante group has a liaison account, a portal or a contact number',
    'AMOTEKUN': 'a South-West outfit with no presence in Plateau; Operation Safe '
                "Haven ('OPSH') is the joint task force that covers this state",
}

# THERE IS A SECOND, LEGITIMATE CONCEPT, AND IT IS NOT THIS ONE.
#
# "Which organisation does this officer belong to" is a different question from
# "which outside agency was this incident handed to". The first is a badge on a
# member of Operation Rainbow's own roster — Operation Rainbow itself, the
# police, the army, a vigilante outfit — stored in `profiles.agency` and drawn
# in the staff directory. The second is a destination with a liaison account, a
# portal and a phone number, stored in `alerts.escalated_to_agency`.
#
# Conflating them is what produced the defect this check exists for, so the
# answer is not to force the two lists together: it is to say which file owns
# which. Each exemption is written out because a blanket skip would have let the
# escalation menu back in.
OWNS_STAFF_BADGES = {
    'src/lib/tactical_mapping.ts':
        'declares STATE_SECURITY_AGENCIES: the parent organisation of a member '
        'of staff, worn as a badge. Never written to escalated_to_agency.',
    'src/components/AdminDirectory.tsx':
        'draws a staff member\'s badge from STATE_SECURITY_AGENCIES.',
    'src/components/MassBroadcast.tsx':
        'addresses an advisory, not an incident — and its agency control is '
        'currently read by nothing at all. See the broadcast finding in '
        'E2E_AUDIT_REPORT.md; this exemption goes when that is closed.',
}

def strip_comments(text: str) -> str:
    """Remove // and /* */ comments, so prose about an agency is not a declaration."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def canonical_codes() -> list[str]:
    body = SOURCE.read_text()
    match = re.search(r'export const AGENCY_CODES = \[(.*?)\] as const;', body, re.S)
    if not match:
        raise SystemExit(f'✗ {SOURCE.relative_to(REPO)} has no AGENCY_CODES array')
    return re.findall(r"'([A-Z]+)'", match.group(1))


def main() -> int:
    codes = canonical_codes()
    problems: list[str] = []

    # ── 1. The owning module is internally complete ─────────────────────────
    body = SOURCE.read_text()
    for table in ('AGENCY_NAMES', 'AGENCY_CHROME'):
        block = re.search(rf'{table}[^=]*= \{{(.*?)\n\}};', body, re.S)
        if not block:
            problems.append(f'agencies.ts has no {table}')
            continue
        listed = set(re.findall(r'^\s*([A-Z]+)\s*:', block.group(1), re.M))
        for code in codes:
            if code not in listed:
                problems.append(f'agencies.ts: {table} has no entry for {code}')
        for extra in sorted(listed - set(codes)):
            problems.append(f'agencies.ts: {table} describes {extra}, which is '
                            f'not in AGENCY_CODES')

    # ── 2. Nobody else spells the list out ──────────────────────────────────
    #
    # Two codes as string literals in a file that keys off an agency is a list,
    # and a list is a second opinion. One literal is a default ('POLICE' when a
    # liaison has no agency recorded) and is fine.
    for rel in CONSUMERS:
        text = strip_comments((CONSOLE / rel).read_text())
        found = {c for c in codes if re.search(rf"['\"]{c}['\"]", text)}
        if len(found) > 1:
            problems.append(
                f'{rel} spells out {len(found)} agency codes '
                f'({", ".join(sorted(found))}). The list lives in '
                f'src/lib/agencies.ts — import AGENCY_LIST or AGENCY_CODES.')

    # A whole new copy, anywhere in the console. Four or more of the six in one
    # file is a declaration of the set, whatever it is called; the two files that
    # legitimately name a couple of agencies never reach four.
    for path in sorted((CONSOLE / 'src').rglob('*.ts*')):
        rel = path.relative_to(CONSOLE).as_posix()
        if rel == 'src/lib/agencies.ts' or '.test.' in rel or rel in CONSUMERS:
            continue
        text = strip_comments(path.read_text())
        found = {c for c in codes if re.search(rf"['\"]{c}['\"]", text)}
        if len(found) >= 4:
            problems.append(
                f'{rel} declares its own list of agencies '
                f'({", ".join(sorted(found))}). That is what the escalation menu '
                f'did. Import AGENCY_LIST from src/lib/agencies.ts.')

    # ── 3. No retired code is used where an agency code is meant ────────────
    #
    # Scoped to the files that key off `escalated_to_agency`. Elsewhere 'RAINBOW'
    # and 'NPF' are staff badges and mean something real — see OWNS_STAFF_BADGES.
    for rel in CONSUMERS:
        text = strip_comments((CONSOLE / rel).read_text())
        if rel in OWNS_STAFF_BADGES:
            continue
        # The dashboard holds both concepts: the escalation menu AND the staff
        # directory, where `p.agency || 'RAINBOW'` is a badge for an officer with
        # no organisation recorded. Its escalation menu is covered exactly, and
        # more strictly, by check 5 below: no hand-written option value at all.
        if rel == 'src/app/dashboard/page.tsx':
            continue
        for retired, why in RETIRED.items():
            if re.search(rf"['\"]{retired}['\"]", text):
                problems.append(f'{rel} uses {retired!r} as an agency: {why}.')

    # Each exemption must still point at a file that exists, or it is a hole
    # nobody is watching.
    for rel in OWNS_STAFF_BADGES:
        if not (CONSOLE / rel).exists():
            problems.append(f'{rel} is exempted from this check and no longer '
                            f'exists — remove the exemption.')

    # ── 4. The consumers import the vocabulary ──────────────────────────────
    for rel in CONSUMERS:
        text = (CONSOLE / rel).read_text()
        if "from './agencies'" not in text and "from '@/lib/agencies'" not in text:
            problems.append(f'{rel} keys off an agency code but does not import '
                            f'it from src/lib/agencies.ts')

    # ── 5. The escalation menu offers codes, not hand-written labels ────────
    page = (CONSOLE / 'src/app/dashboard/page.tsx').read_text()
    menu = re.search(r'TARGET INTER-AGENCY COMMAND(.*?)</select>', page, re.S)
    if not menu:
        problems.append('dashboard/page.tsx: the escalation menu was not found — '
                        'if it moved, point this check at it')
    else:
        literals = re.findall(r'<option value="([^"]*)"', menu.group(1))
        for value in literals:
            if value != 'ALL':
                problems.append(
                    f'the escalation menu hard-codes <option value="{value}">. '
                    f'It must be built from AGENCY_LIST, or it will drift from '
                    f'the portal and the contact lookup again.')

    # ── 6. Every code has contact variables, and no code has spare ones ─────
    env = (CONSOLE / '.env.example').read_text()
    declared = set(re.findall(r'^([A-Z0-9_]+)_LIAISON_PHONE=', env, re.M))
    declared_hooks = set(re.findall(r'^([A-Z0-9_]+)_WEBHOOK_URL=', env, re.M))
    for code in codes:
        if code not in declared:
            problems.append(f'hq-dashboard-next/.env.example has no '
                            f'{code}_LIAISON_PHONE, so no deployment can be told '
                            f'where to reach {code}')
        if code not in declared_hooks:
            problems.append(f'hq-dashboard-next/.env.example has no '
                            f'{code}_WEBHOOK_URL')
    for extra in sorted((declared | declared_hooks) - set(codes)):
        problems.append(f'hq-dashboard-next/.env.example configures contacts for '
                        f'{extra}, which is not an agency this console can '
                        f'escalate to — an operator would fill it in for nothing')

    # ── 7. The configuration report covers the same six ─────────────────────
    report = (REPO / 'scripts' / 'what_is_not_configured.py').read_text()
    block = re.search(r"for _code, _name in \((.*?)\):", report, re.S)
    if not block:
        problems.append('scripts/what_is_not_configured.py: the agency loop was '
                        'not found')
    else:
        listed = re.findall(r"\('([A-Z]+)',", block.group(1))
        if sorted(listed) != sorted(codes):
            problems.append(
                f'scripts/what_is_not_configured.py reports on '
                f'{", ".join(sorted(listed))}; the agencies are '
                f'{", ".join(sorted(codes))}. An operator would be told to '
                f'configure the wrong set.')

    for p in problems:
        print(f'✗ {p}', file=sys.stderr)
    if problems:
        print(f'\n{len(problems)} problem(s): more than one agency vocabulary.',
              file=sys.stderr)
        return 1

    print(f'✓ one agency vocabulary: {", ".join(codes)} — declared in '
          f'src/lib/agencies.ts, and the escalation menu, the liaison form, the '
          f'portal, the contact lookup, the env template and the configuration '
          f'report are all built from it')
    return 0


if __name__ == '__main__':
    sys.exit(main())
