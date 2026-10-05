#!/usr/bin/env python3
"""Exactly one deploy target may be configured, and it is Railway.

    python3 scripts/check_one_deploy_target.py

This repository carried TWO complete, mutually contradictory deploy
configurations for the HQ console at the same time, for a month:

    Firebase App Hosting   firebase.json (backend `rainbow-hq`),
                           hq-dashboard-next/apphosting.yaml,
                           deploy.sh -> `firebase deploy --only apphosting`
    Railway                hq-dashboard-next/railway.json, docs/RAILWAY.md

Each was documented as though it were the live one. README.md said "Firebase App
Hosting … then ./deploy.sh"; docs/PRODUCTION_DEPLOYMENT.md said "Railway ←
current target" twenty lines above a full App Hosting runbook; and `deploy.sh`,
the script literally named "production deploy", pushed to the target that had
been abandoned. Anybody told to redeploy had even odds of shipping to a dead
backend and then watching a stale console keep answering requests — which is
indistinguishable, from the outside, from a deploy that worked.

It was not a documentation problem. Two live configs mean two sets of
environment variables, two secret stores and two places a build can be green, so
the question "what is running right now?" has no answer in the repository.

Hence this check, with one rule: the repo may configure Railway and nothing else.
It is a file-shape check, not a judgement about what is good — adding a target is
fine, as long as it REPLACES the one that is there and this list is updated in
the same commit.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Config files that mean "this repo deploys to <provider>". A path here is a
# failure by its existence alone.
FORBIDDEN_CONFIG = {
    'firebase.json': 'Firebase (App Hosting or Hosting)',
    '.firebaserc': 'Firebase',
    'hq-dashboard-next/apphosting.yaml': 'Firebase App Hosting',
    'hq-dashboard-next/firebase.json': 'Firebase',
    'vercel.json': 'Vercel',
    'hq-dashboard-next/vercel.json': 'Vercel',
    'netlify.toml': 'Netlify',
    'hq-dashboard-next/netlify.toml': 'Netlify',
    'fly.toml': 'Fly.io',
    'hq-dashboard-next/fly.toml': 'Fly.io',
    'render.yaml': 'Render',
    'app.yaml': 'Google App Engine',
    'Procfile': 'a Procfile-based host',
}

# The one that must be present. Its absence is also a failure: a repo with no
# deploy config at all is the same unanswerable question in the other direction.
REQUIRED_CONFIG = 'hq-dashboard-next/railway.json'

# Deploy COMMANDS in scripts and workflows. A config file can be stale and
# harmless; an invocation is something that will actually run.
FORBIDDEN_COMMANDS = [
    (re.compile(r'\bfirebase\s+deploy\b'), '`firebase deploy`'),
    (re.compile(r'\bfirebase\s+apphosting:'), 'the `firebase apphosting:` CLI'),
    (re.compile(r'\bvercel\s+(?:deploy|--prod)\b'), '`vercel deploy`'),
    (re.compile(r'\bnetlify\s+deploy\b'), '`netlify deploy`'),
    (re.compile(r'\bflyctl?\s+deploy\b'), '`fly deploy`'),
]

# Where a command would actually run. Prose may name any provider it likes —
# docs/RAILWAY.md and docs/PRODUCTION_DEPLOYMENT.md both discuss App Hosting on
# purpose, because "what moving off it cost us" is the reason the client-bundle
# secret scan is now the only line of defence, and that is worth writing down.
EXECUTABLE_GLOBS = ['*.sh', 'scripts/*.sh', '.github/workflows/*.yml',
                    'hq-dashboard-next/package.json']


def main() -> int:
    problems: list[str] = []

    for rel, provider in sorted(FORBIDDEN_CONFIG.items()):
        if (REPO / rel).exists():
            problems.append(
                f'{rel} exists, which configures {provider}. The console deploys '
                f'to Railway. Remove it, or if the target really has changed, '
                f'swap the entries in this check in the same commit.')

    if not (REPO / REQUIRED_CONFIG).is_file():
        problems.append(
            f'{REQUIRED_CONFIG} is missing — nothing in this repository says '
            f'where the console deploys to.')

    for glob in EXECUTABLE_GLOBS:
        for path in sorted(REPO.glob(glob)):
            text = path.read_text(encoding='utf-8', errors='replace')
            for lineno, line in enumerate(text.splitlines(), 1):
                # A comment explaining what the script USED to do is not a
                # command. deploy.sh documents its own history on purpose.
                stripped = line.lstrip()
                if stripped.startswith('#') or stripped.startswith('//'):
                    continue
                for pattern, what in FORBIDDEN_COMMANDS:
                    if pattern.search(line):
                        problems.append(
                            f'{path.relative_to(REPO)}:{lineno} runs {what}. '
                            f'Railway deploys on push; there is no deploy '
                            f'command in this repository.')

    for p in problems:
        print(f'✗ {p}', file=sys.stderr)
    if problems:
        print(f'\n{len(problems)} problem(s): more than one deploy target.',
              file=sys.stderr)
        return 1

    print('✓ one deploy target: Railway '
          f'({REQUIRED_CONFIG}), and no deploy command in any script')
    return 0


if __name__ == '__main__':
    sys.exit(main())
