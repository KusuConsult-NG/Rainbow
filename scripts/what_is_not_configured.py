#!/usr/bin/env python3
"""Which features are switched off because a key is blank, and what each costs.

    python3 scripts/what_is_not_configured.py
    python3 scripts/what_is_not_configured.py --check   # CI: the map must be complete

Reads the real env files if they exist, falls back to the `.env.example` key
list, and says per key: configured, blank, or absent — never the value.

**It describes the checkout it runs in, not the deployment.** The console runs
on Railway, where variables are set in the service's own settings and never in a
file here, so a clean checkout reports almost everything absent while production
is fine. For the app's `.env` the opposite holds: that file is bundled into the
APK at build time, so for the mobile keys this IS the authoritative source.

## Why this is a script and not a paragraph

"What is left?" has been asked three times, and each time the answer was prose
written from memory, which went stale the moment a key was added or filled in.
Two of this audit's findings (T-21, T-22) are exactly that failure in another
costume: a hand-maintained statement of state, believed because it was
confident.

So the key list is DERIVED from `.env.example` — both of them — and
`--check` fails if a key appears there that this file cannot explain. Adding a
setting therefore forces someone to say what breaks without it, which is the
only part a reader actually needs.

## What it deliberately does not do

It does not read the database, so it cannot tell you how many staff accounts
exist (T-19), whether the Send SMS hook is enabled (that is
`wire_up_sms_provider.sh --check`), or whether the Cloud Functions are deployed
(C-6). It reports what is knowable from the filesystem, and names the tool for
each thing that is not.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Each key: (tier, what is off without it, what a person sees).
#
# Tier 1 is "the system does not work for the people it is for". Tier 2 is a
# feature that silently does nothing. Tier 3 is build and release plumbing.
FEATURES: dict[str, tuple[int, str, str]] = {
    # ── the app's bundled .env ───────────────────────────────────────────────
    'MESH_HQ_PUBLIC_KEY': (
        2, 'the offline mesh cannot seal anything to HQ',
        'a handset with no network queues reports it can never deliver'),
    'MAP_TILE_URL': (
        2, 'the app map has no tiles',
        'the map renders as empty space with markers floating on it'),
    'HQ_API_BASE_URL': (
        2, 'the app cannot reach the console API',
        'mesh ingest and SMS fallback have nowhere to post'),
    'CLOUDINARY_CLOUD_NAME': (
        2, 'photo and video evidence cannot upload',
        'attaching media to a report fails'),
    'CLOUDINARY_UPLOAD_PRESET': (
        2, 'photo and video evidence cannot upload',
        'attaching media to a report fails'),
    'DEMO_CITIZEN_EMAIL': (
        3, 'nothing — a demonstration account only',
        'no effect on a real deployment'),

    # ── the console's .env.local ─────────────────────────────────────────────
    'NEXT_PUBLIC_SUPABASE_URL': (
        1, 'the console cannot reach the database at all',
        'every screen is empty or errors'),
    'NEXT_PUBLIC_SUPABASE_ANON_KEY': (
        1, 'the console cannot authenticate anyone',
        'nobody can sign in to the console'),
    'SUPABASE_SERVICE_ROLE_KEY': (
        1, 'server-side routes that bypass RLS cannot run',
        'mesh ingest, SMS ingest and the outbox drain all refuse'),
    'MESH_HQ_PRIVATE_KEY': (
        2, 'mesh ingest refuses every envelope',
        'route.ts logs "MESH_HQ_PRIVATE_KEY is not configured — refusing"'),
    'GEMINI_API_KEY': (
        2, 'the AI forensic debrief cannot be generated',
        'the dossier shows no AI summary'),
    'ONESIGNAL_APP_ID': (
        2, 'push notifications are not delivered',
        'an escalation queues in the outbox and nobody is woken'),
    'ONESIGNAL_REST_API_KEY': (
        2, 'push notifications are not delivered',
        'an escalation queues in the outbox and nobody is woken'),
    'SOS_DISPATCH_PHONE': (
        2, 'the dispatch callback number is unset',
        'HQ has no number to ring back on an SOS'),
    'RAINBOW_WEBHOOK_SECRET': (
        2, 'agency webhooks cannot be signed',
        'an incident handed to an outside agency is not delivered by webhook'),
    'NEXT_PUBLIC_MAP_TILE_URL': (
        2, 'the console map has no tiles',
        'the live map renders as empty space'),
    'TERMII_API_KEY': (
        1, 'no SMS can be sent, including sign-in codes',
        'every citizen sign-in fails — see T-18'),
    'TERMII_SENDER_ID': (
        2, 'SMS is sent from an unapproved sender',
        'Termii may reject the message'),
    'SEND_SMS_HOOK_SECRET': (
        1, 'the Send SMS hook refuses to run',
        'every citizen sign-in fails — see T-18'),
    'ALLOW_UNSENT_OTP': (
        3, 'nothing — and it must stay unset',
        'set, it lets auth proceed when no code was sent, so the app tells '
        'somebody a code is coming when none is'),

    # ── the offline channels ────────────────────────────────────────────────
    'SMS_EMERGENCY_SHORTCODE': (
        2, 'the encrypted SMS fallback has nowhere to send',
        'the app skips SMS entirely rather than paying to send a message that '
        'reaches nobody'),
    'SMS_GATEWAY_SECRET': (
        2, 'the inbound SMS gateway callback is unauthenticated',
        'a caller who finds the route can post traffic — though each message '
        'is still separately authenticated by the handset device key, so an '
        'alert cannot be forged with this alone'),
    'USSD_GATEWAY_SECRET': (
        2, 'the USSD callback is unauthenticated',
        'it removes the one thing this channel trusts — that the CARRIER '
        'asserted the number — so a stranger could file as anyone'),
    'USSD_REPLY_FORMAT': (
        3, 'nothing — AT_TEXT is the default and is correct',
        'set it to JSON only if your gateway requires it'),
    'ONESIGNAL_AUTH_SCHEME': (
        3, 'nothing — both schemes are tried',
        'the first is retried if refused, and the log says which to pin'),
}

# The six agencies this console hands incidents to. Generated rather than
# written out twelve times: the list is the same one 20261003000000 recognises
# as outside agencies, and a loop cannot get one of the twelve wrong.
for _code, _name in (
    ('POLICE', 'the Police'), ('ARMY', 'the Army'), ('DSS', 'the DSS'),
    ('NSCDC', 'the NSCDC'), ('FRSC', 'the FRSC'),
    ('OPSH', 'Operation Enduring Peace'),
):
    FEATURES[f'{_code}_WEBHOOK_URL'] = (
        2, f'an incident handed to {_name} is not delivered by webhook',
        'it is escalated in the database and the agency is never told')
    FEATURES[f'{_code}_LIAISON_PHONE'] = (
        2, f'HQ has no callback number for {_name}',
        'the dossier shows no contact for the agency the incident went to')

# Keys in .env.example that are documentation rather than settings: section
# headers, examples inside comments, and names the file mentions only to say
# they were REMOVED. Each needs to be here deliberately, so the --check below
# cannot be satisfied by a blanket skip.
NOT_SETTINGS = {
    'AGENT_DEFAULT_PASS': 'removed in PR #61 — it was one shared staff password, published in the APK (T-20)',
    'DEMO_CITIZEN_PASS': 'removed in PR #61 for the same reason',
    'HOOK_SECRET': 'the legacy name; the hook refuses to run if only this is set',
    'MESH_KEYGEN': 'a test-only flag for printing a fresh mesh keypair',
    'TERMII_BASE_URL': 'optional override of the Termii endpoint; the default is correct',
    'NEXT_PUBLIC_GEMINI_API_KEY': 'removed — Next.js inlined it into the client bundle',
    'NEXT_PUBLIC_DEV_DEMO_PIN': (
        'development only, and verified so: login/page.tsx gates the quick-fill '
        'presets on `process.env.NODE_ENV !== "production"` and the array folds '
        'to [] otherwise, so the references are eliminated from a production '
        'bundle. The CI scan of .next/static for PIN/PASS/SECRET/TOKEN is the '
        'second line if that ever regresses'),
}

ENV_FILES = [
    ('the app (bundled into the APK)', Path('.env'), Path('.env.example')),
    ('the console', Path('hq-dashboard-next/.env.local'),
     Path('hq-dashboard-next/.env.example')),
]

PLACEHOLDER = re.compile(
    r'^(your|changeme|xxx+|<|\.\.\.|replace|todo|example|dummy|local-e2e)', re.I)


def parse(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text(errors='replace').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, _, v = line.partition('=')
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def state(value: str | None) -> str:
    if value is None:
        return 'ABSENT'
    if not value:
        return 'BLANK'
    if PLACEHOLDER.match(value):
        return 'PLACEHOLDER'
    return 'set'


def main() -> int:
    check = '--check' in sys.argv
    unexplained: list[str] = []
    rows: list[tuple[int, str, str, str, str, str]] = []

    for label, real, example in ENV_FILES:
        keys = parse(REPO / example)
        actual = parse(REPO / real)
        have_real = (REPO / real).exists()
        for key in keys:
            if key in NOT_SETTINGS:
                continue
            if key not in FEATURES:
                unexplained.append(f'{example}: {key}')
                continue
            tier, off, seen = FEATURES[key]
            st = state(actual.get(key) if have_real else keys.get(key))
            rows.append((tier, label, key, st, off, seen))

    if check:
        if unexplained:
            print('✗ these keys are in an .env.example and this script cannot '
                  'say what breaks without them:', file=sys.stderr)
            for u in unexplained:
                print(f'    {u}', file=sys.stderr)
            print('\n  Add them to FEATURES (with the tier and what a person '
                  'sees) or to NOT_SETTINGS with a reason.', file=sys.stderr)
            return 1
        print(f'✓ every key in both .env.example files is explained '
              f'({len(FEATURES)} settings, {len(NOT_SETTINGS)} non-settings)')
        return 0

    missing_t1 = [r for r in rows if r[0] == 1 and r[3] != 'set']
    for tier, title in ((1, 'STOPS THE SYSTEM WORKING'),
                        (2, 'a feature silently does nothing'),
                        (3, 'no operational effect')):
        group = [r for r in rows if r[0] == tier and r[3] != 'set']
        if not group:
            continue
        print(f'\n── tier {tier}: {title} ' + '─' * max(0, 52 - len(title)))
        for _, label, key, st, off, seen in sorted(group, key=lambda r: r[2]):
            print(f'  {st:12s} {key}   [{label}]')
            print(f'               {off}')
            print(f'               → {seen}')

    ok = [r for r in rows if r[3] == 'set']
    print(f'\n{len(ok)} of {len(rows)} settings are configured '
          f'IN THIS CHECKOUT.')

    # This is the thing most likely to be misread, so it is stated at the point
    # the number appears rather than in a header nobody scrolls back to. The
    # console is deployed on Railway, where variables live in the service's own
    # settings and never in a file in the repository. A local checkout therefore
    # reports almost everything absent while production is fully configured —
    # and the reverse is just as possible. The first draft of this script
    # printed the count with no such note, which would have read as "your
    # production deployment is 2 of 35 configured".
    placeholders = [r for r in rows if r[3] == 'PLACEHOLDER']
    print('\n  ⚠ This reads the files in THIS checkout, not your deployment.')
    print('    The console runs on Railway: its variables are set in the')
    print('    Railway service settings (Variables tab), and nothing in this')
    print('    repository can see them. Treat the list above as "what a fresh')
    print('    checkout is missing", and check Railway for what production has.')
    if placeholders:
        print(f'    {len(placeholders)} value(s) here are test placeholders '
              f'(e.g. local-e2e…), which is')
        print('    what a development checkout is supposed to contain.')
    print('    The app\'s .env is different: it is bundled into the APK at')
    print('    build time, so for the MOBILE keys this file is authoritative.')

    print('\nNot knowable from the filesystem — each has its own tool:')
    print('  is the Send SMS hook enabled?   '
          './scripts/wire_up_sms_provider.sh --check')
    print('  did the last migrations land?   '
          'scripts/did_the_convergence_land.sql')
    print('  how many staff accounts exist?  the console roster (T-19)')
    print('  are the Cloud Functions live?   '
          'gcloud functions list --project rainbow-97f1e (C-6)')

    kp = REPO / 'android' / 'key.properties'
    if not kp.exists():
        print('\nAlso: android/key.properties is absent, so a release build is '
              'unsigned\n  (android/app/build.gradle.kts reads it for the '
              'release signingConfig).')

    return 1 if missing_t1 else 0


if __name__ == '__main__':
    sys.exit(main())
