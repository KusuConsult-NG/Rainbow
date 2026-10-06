#!/usr/bin/env python3
"""Does this object name actually exist in the migrations, or did someone invent it?

    python3 scripts/is_this_object_real.py set_emergency_pin mesh_messages
    python3 scripts/is_this_object_real.py --stdin < names.txt

Prints, per name: whether any migration in supabase/migrations/ creates it, which
one, and — when it does not exist — the closest real name, because the usual
cause is a plausible-sounding near-miss rather than a typo.

## Why this exists

On 2026-10-06 a migration-status table was pasted in reporting twenty-four
objects `MISSING from public schema`, among them the mesh tables and the
emergency-PIN functions, and concluding that nine migrations were unapplied or
partial. A verdict table from the same database, pasted beside it, reported
`emergency PIN functions exist (4)`, `the mesh can recognise the same envelope
arriving twice` and `mesh traffic is not readable through the API` — all PASS.

Both cannot be right. Checking every name against the migrations settled it in
one pass: all twenty-four appear in NO migration in this repository. They are
near-misses for the real objects —

    set_emergency_pin                    ->  set_emergency_pins
    mesh_messages / nodes / sync_log     ->  mesh_envelopes_seen
    ingest_mesh_message                  ->  mesh_note_envelope
    register_sms_device_key              ->  register_sms_device
    tier_timeout                         ->  tier_timeout_minutes
    is_agency_liaison                    ->  is_liaison
    profiles.pin_salt, safe_pin_hash...  ->  the emergency_pins TABLE

— and the last of those is the giveaway: the PIN hashes were deliberately moved
OFF profiles into their own table so the API roles cannot read them, which is
the `PIN hashes unreadable by the API roles` check. A diagnostic looking for
them as profiles columns is describing a schema this project rejected.

Acting on it would have meant re-applying nine already-applied migrations. That
is the same trap as T-21, arriving from outside the repository: no script here
emits that wording, so it was written from memory of what the schema probably
contains rather than extracted from the files. `check_schema_convergence.py`
records the same failure mode from the inside — "a hand-written version was
tried first and was substantially wrong; it invented names and missed real
ones".

So this is the cheap rebuttal: it needs no database, no credentials and no
network, and it answers the only question that matters about such a claim —
is this a thing we ever create?

## What it cannot tell you

Whether the object exists in YOUR database. It reads the migrations, not a live
schema. A name it confirms as real may still be genuinely missing from a
database that never had the migration — that is what
scripts/which_migrations_are_applied.sql is for, run against the database
itself. This answers the prior question, and the one that was wrong here.
"""
from __future__ import annotations

import difflib
import importlib.util
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location(
    'smi', REPO / 'scripts' / 'sync_migration_inventory.py')
_smi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_smi)


def known() -> tuple[dict[str, tuple[str, str, bool]], list[str]]:
    """({name: (migration, kind, must_exist)}, [every name for suggestions])."""
    rows, _ = _smi.inventory()
    index: dict[str, tuple[str, str, bool]] = {}
    for stem, kind, obj, want in rows:
        # A column is reachable by its bare name and its qualified one, since a
        # claim may be written either way.
        for key in ({obj, obj.split('.')[-1]} if kind == 'column' else {obj}):
            index.setdefault(key, (stem, kind, want))
    return index, sorted(index)


def main(argv: list[str]) -> int:
    names: list[str] = [a for a in argv if not a.startswith('--')]
    if '--stdin' in argv:
        names += [line.strip() for line in sys.stdin if line.strip()]
    if not names:
        print(__doc__.strip().split('\n\n')[1], file=sys.stderr)
        print('\nGive one or more object names, or --stdin.', file=sys.stderr)
        return 2

    index, universe = known()
    invented = 0
    for raw in names:
        # Tolerate the shapes a pasted diagnostic uses: "function foo",
        # "column alerts.bar", "table baz", "public.foo".
        name = raw.strip().rstrip(',;')
        for prefix in ('function ', 'column ', 'table ', 'public.'):
            if name.lower().startswith(prefix):
                name = name[len(prefix):]
        hit = index.get(name) or index.get(name.split('.')[-1])
        if hit:
            stem, kind, want = hit
            state = 'created by' if want else 'DROPPED by'
            print(f'✓ {raw}\n    real: {kind}, {state} {stem}')
            if not want:
                print('    so it SHOULD be absent from a database that has '
                      'every migration')
        else:
            invented += 1
            close = difflib.get_close_matches(
                name.split('.')[-1], universe, n=3, cutoff=0.6)
            print(f'✗ {raw}\n    NO migration in this repository creates this.')
            if close:
                print(f'    closest real name(s): {", ".join(close)}')
            else:
                print('    and nothing close — the claim is about a different '
                      'schema entirely.')

    print(f'\n{len(names) - invented} real, {invented} not in any migration.')
    if invented:
        print('A diagnostic naming objects this project never creates is '
              'describing some other schema.\nDo not apply migrations on its '
              'say-so — run scripts/which_migrations_are_applied.sql against '
              'the\ndatabase instead.')
    return 1 if invented else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
