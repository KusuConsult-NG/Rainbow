#!/usr/bin/env python3
"""Split scripts/apply_all_migrations.sql into pasteable parts.

WHY THIS EXISTS
---------------
`apply_all_migrations.sql` is 2,300-odd lines and is meant to go into a SQL
editor as ONE paste, which is the safest way to run it: you cannot get the order
wrong and you cannot stop halfway by accident.

But a single paste of that size is not always practical — a browser tab that
struggles with it, a connection that drops mid-statement, or simply an operator
who wants to see each migration land before starting the next. The alternative
people reach for in that situation is copying chunks out of the big file by hand,
which is exactly how a migration gets skipped or run out of order. So the split
is generated, in order, numbered, with the ordering requirement written into
every part.

Each part is one migration plus the `NOTICE: applying ...` banner the generator
already wrote around it, and the last part is the verification block, which
writes nothing and returns 25 PASS/FAIL rows.

WHAT MAKES THIS SAFE RATHER THAN A FOOTGUN
------------------------------------------
`scripts/verify_apply_in_parts.sh` applies the parts in order against a
production-shaped PostgreSQL and asserts the same 25 PASS rows the single paste
produces. CI runs it. So "the parts are equivalent to the whole" is a checked
claim, not a hope.

Regenerate after any migration change:
    python3 scripts/build_apply_all.py && python3 scripts/build_apply_in_parts.py
"""
import pathlib
import re
import shutil
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "scripts/apply_all_migrations.sql"
OUT = ROOT / "scripts/apply_in_parts"

NOTE = """--
-- ONE PART OF scripts/apply_all_migrations.sql — generated, do not edit by hand.
--   Regenerate with: python3 scripts/build_apply_in_parts.py
--
-- Run the parts IN NUMBER ORDER, each on its own, letting each finish before the
-- next. The order is not cosmetic: part 02 drops the permissive policy set BY
-- NAME, and several later parts assume columns an earlier part adds.
--
-- Expect `NOTICE: skipping ...` lines — they are the guards that let these files
-- run against a database that does not have a given table yet.
--
-- ONE PART BEHAVES DIFFERENTLY IF YOU RUN IT TWICE. Part 02, the RLS policy
-- migration, is ATOMIC rather than idempotent: it drops the old policy set by
-- name and creates a new one inside its own BEGIN/COMMIT. Run it a second time
-- and it says
--
--     ERROR: policy "profiles_select_self_or_staff" for table "profiles"
--            already exists
--
-- and rolls itself back. That message means THE POLICIES ARE ALREADY IN PLACE.
-- Nothing is half-applied, and part 15 will still report every row PASS.
--
-- Part 15 is the readout: it writes nothing and tells you the truth about the
-- whole set. It needs parts 01-14 applied first, because it checks work they do;
-- run it early and it says so plainly rather than failing on a missing function.
--
-- The LAST part writes nothing. It returns one row per thing that had to be
-- true, and every one of them must read PASS.
--
-- If you can paste the whole of apply_all_migrations.sql in one go, do that
-- instead: one paste cannot be run out of order or stopped halfway by accident.
--

"""


# ── A readable precondition, instead of 42883 ───────────────────────────────
#
# The verification block is ONE query, and it calls functions the earlier parts
# create. Run it before them and PostgreSQL cannot even plan it:
#
#   ERROR: 42883: function public.next_tier(unknown) does not exist
#   LINE 124: (SELECT public.next_tier('HQ') IS NULL AND ...
#
# That is a parse-time failure, so no amount of AND-guarding inside the query
# avoids it — the missing object has to be caught before the query is reached.
# In the single-paste flow this never happens, because everything is applied
# first. In the parts flow somebody will inevitably run the last one early, to
# see where they stand, and be told something that sounds like database damage.
VERIFY_GUARD = """
-- ── Are the parts before this one actually applied? ─────────────────────────
--
-- This part is one query that calls functions the earlier parts create. Without
-- them PostgreSQL cannot plan it at all and reports
-- `42883: function public.next_tier(unknown) does not exist`, which sounds far
-- worse than it is. So it checks first and tells you what is missing.
DO $precheck$
DECLARE
  missing TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF to_regclass('public.emergency_pins') IS NULL THEN
    missing := missing || ARRAY['part 03 (emergency_pins)']; END IF;
  IF to_regprocedure('public.next_tier(text)') IS NULL THEN
    missing := missing || ARRAY['part 11 (next_tier)']; END IF;
  IF to_regprocedure('public.purge_stale_telemetry()') IS NULL THEN
    missing := missing || ARRAY['part 12 (purge_stale_telemetry)']; END IF;
  IF to_regclass('public.sms_device_keys') IS NULL THEN
    missing := missing || ARRAY['part 13 (sms_device_keys)']; END IF;
  IF to_regclass('public.mesh_envelopes_seen') IS NULL THEN
    missing := missing || ARRAY['part 14 (mesh_envelopes_seen)']; END IF;

  IF array_length(missing, 1) > 0 THEN
    RAISE EXCEPTION
      'NOT READY: run the earlier parts first. Missing: %. '
      'Nothing is wrong with the database — this part only checks work the '
      'other parts do.', array_to_string(missing, ', ');
  END IF;
END $precheck$;

"""


def sections(lines: list[str]) -> list[tuple[int, str]]:
    """Where each migration starts, and what it is called.

    The date pattern is `2026\\d+`, NOT `20260\\d+`. An earlier version of this
    anchored on the fifth digit and silently skipped
    `20261001000000_mesh_ingest.sql` — the split came out one part short and
    nothing said so, because a missing section is not a syntax error.
    """
    found: list[tuple[int, str]] = []
    for i, line in enumerate(lines):
        if re.match(r"^-- (2026\d+_|phase\d)", line) and lines[i - 1].startswith("-- ---"):
            found.append((i - 1, line[3:].strip()))
        elif line.startswith("-- DID IT WORK?"):
            found.append((i - 1, "VERIFY.sql"))
    return found


def main() -> int:
    if not SRC.exists():
        print(f"{SRC} is missing — run build_apply_all.py first", file=sys.stderr)
        return 1

    lines = SRC.read_text().splitlines(keepends=True)
    found = sections(lines)

    migrations = sorted(
        p.name for p in (ROOT / "supabase/migrations").glob("*.sql")
    )
    historical = {
        "20260720000000_initial_schema.sql",
        "phase1_foundation.sql",
        "phase2_assigned_responders.sql",
        "phase3_profile_columns_and_config.sql",
    }
    expected = len([m for m in migrations if m not in historical]) + 1  # + VERIFY
    if len(found) != expected:
        print(
            f"found {len(found)} sections but expected {expected} "
            f"({expected - 1} migrations + the verification block). "
            f"The banner format in apply_all_migrations.sql has changed.",
            file=sys.stderr,
        )
        return 1

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    for n, (start, name) in enumerate(found, start=1):
        end = found[n][0] if n < len(found) else len(lines)
        label = name.replace(".sql", "")
        body = "".join(lines[start:end])
        # Only the verification part needs the precondition; the migrations carry
        # their own guards and are meant to run against a database that does not
        # have a given table yet.
        if label == "VERIFY":
            body = VERIFY_GUARD + body
        (OUT / f"{n:02d}_{label}.sql").write_text(NOTE + body)

    print(f"wrote {len(found)} parts to {OUT.relative_to(ROOT)}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
