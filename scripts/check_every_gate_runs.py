#!/usr/bin/env python3
"""A gate wired into nothing is a gate that does not exist.

    python3 scripts/check_every_gate_runs.py

## What went wrong

`scripts/check_non_emergency_categories_agree.py` was written with T-47,
mutation-tested six ways, and **wired into nothing**. It kept the app's two
non-emergency category labels and the SQL's one list in agreement — on a
developer's machine, if they thought to run it. Nothing ran it on a push, so a
category renamed on one side and not the other would have sailed through: a
destroyed culvert filed as an emergency, pushed to the field responders at
02:00 and escalated to HQ by morning, which is the exact failure T-47 exists to
prevent.

It was found by asking a question nothing had asked — *is every gate in this
directory actually run by CI?* — which is the only way to find this class of
thing. A gate that is never invoked does not fail. It reports nothing, forever,
and reads as coverage in the report that lists it.

## What this checks

Every `scripts/check_*.py` is named either by `.github/workflows/ci.yml` or by
a script that file runs (`verify_*.sh`, which is where the two SQL-replay gates
live). Comment lines are dropped first, because this workflow carries a
paragraph above every gate explaining what it caught — so a step commented out
with its explanation left in place would otherwise still look wired. Names are
matched as whole tokens, so `verify_rls_migration.sh.disabled` does not count
as running `verify_rls_migration.sh`.

## What it does not check

Whether the gate asserts anything useful — that is what mutation-testing each
one is for — or whether CI passes. Only that a push would run it.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SCRIPTS = REPO / 'scripts'
CI = REPO / '.github' / 'workflows' / 'ci.yml'

if not CI.exists():
    print(f'{CI.relative_to(REPO)} does not exist, so nothing runs any gate.')
    sys.exit(1)

def uncommented(text: str) -> str:
    """Drop whole-line comments.

    This workflow explains every gate in a comment paragraph above it, and
    those paragraphs name the gate. A step commented out with its explanation
    left behind would read as wired to any check that just searched the file.
    """
    return '\n'.join(
        line for line in text.split('\n') if not line.lstrip().startswith('#'))


ci = uncommented(CI.read_text())

# The shell scripts CI runs, which is where a gate may legitimately be invoked
# instead of from the workflow directly: check_schema_convergence.py and
# check_generated_column_inserts.py both run inside verify_rls_migration.sh,
# which replays the migrations against real PostgreSQL.
runners = ''
for sh in sorted(SCRIPTS.glob('*.sh')):
    if re.search(rf'(?<![\w-]){re.escape(sh.name)}(?![\w.-])', ci):
        runners += uncommented(sh.read_text())

haystack = ci + runners
unwired = []
gates = sorted(SCRIPTS.glob('check_*.py'))
for gate in gates:
    if not re.search(rf'(?<![\w.-]){re.escape(gate.name)}(?![\w.-])', haystack):
        unwired.append(gate.name)

# This script is the exception that proves itself: it must be wired too, and it
# is above, so no special case is needed.

if unwired:
    print('Gates that exist and are never run:\n')
    for name in unwired:
        print(f'  * scripts/{name} is not named by .github/workflows/ci.yml, '
              'nor by any shell script that file runs. It cannot fail, so it '
              'is not protecting anything. Add a step for it beside the '
              'others.\n')
    print('See scripts/check_every_gate_runs.py for why this matters.')
    sys.exit(1)

print(f'All {len(gates)} gates are run on a push:')
print('  * named by .github/workflows/ci.yml, or by a shell script it runs')
