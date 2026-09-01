#!/usr/bin/env python3
"""Generate scripts/rls_inventory.sql — the read-only policy inventory.

The inventory flags every live policy whose name this repository's migrations do
not create, because those are the ones the least-privilege migration will NOT
drop (it drops by exact name) and which therefore survive it. PostgreSQL ORs
PERMISSIVE policies together, so one survivor re-opens the table.

The list of "known" names is extracted from the migration files rather than
written by hand. A hand-written list was tried first and was substantially
wrong — it invented names like `profiles_self_read` that do not exist and missed
real ones like `alerts_select_own_or_staff`, `safe_zones_read` and the whole
`uninstall_*` family. That failure mode is worse than no list: it labels real
policies as hand-created, and a reader acting on it could drop policies the
application depends on.

    python3 scripts/build_rls_inventory.py
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase/migrations"
OUT = ROOT / "scripts/rls_inventory.sql"

# Comments must not contribute names. `-- CREATE POLICY has no IF NOT EXISTS`
# in phase3 otherwise yields a policy called "has".
COMMENT = re.compile(r"--[^\n]*")
POLICY = re.compile(
    r'(?:CREATE|DROP)\s+POLICY\s+(?:IF\s+EXISTS\s+)?(?:"([^"]+)"|([A-Za-z_]\w*))',
    re.IGNORECASE,
)


def known_policy_names() -> list[str]:
    names: set[str] = set()
    for path in sorted(MIGRATIONS.glob("*.sql")):
        body = COMMENT.sub("", path.read_text())
        for match in POLICY.finditer(body):
            names.add(match.group(1) or match.group(2))
    return sorted(names)


TEMPLATE = """-- ============================================================================
-- STEP 1 of 2 — RLS POLICY INVENTORY.  READ ONLY.  Generated file, do not edit.
--   Regenerate with: python3 scripts/build_rls_inventory.py
--
--   Paste into the Supabase dashboard -> SQL Editor and run. It is one SELECT.
--   It changes nothing, writes nothing, and takes no locks.
--
-- WHY THIS IS SEPARATE FROM THE DRY RUN
--
-- The Supabase SQL Editor shows the result of the LAST row-returning statement
-- and does not surface `RAISE NOTICE` output at all. The first version of the
-- dry run reported everything through NOTICE, so the operator saw one summary
-- row and none of the findings. Anything that must be read has to come back as
-- a result set, and only one of them survives — hence two separate scripts.
--
-- WHAT IT IS FOR
--
-- 20260813000000_rls_least_privilege.sql drops prior policies BY EXACT NAME,
-- from a list built by reading this repo's migration files. A policy created by
-- hand in the dashboard is not in that list, so the migration leaves it in
-- place — and because PostgreSQL combines PERMISSIVE policies with OR, one
-- surviving `USING (true)` re-opens the table and the migration becomes
-- decorative. That is exactly how phase1_foundation.sql already failed once.
--
-- HOW TO READ IT
--
-- `source` is the column that matters. Every `NOT-IN-REPO` row is a policy this
-- repository does not create and the migration will not drop; each has to be
-- accounted for before applying. `reach` separates the two very different kinds
-- of `USING (true)`: one granted to anon/public is an open door, one granted
-- only to `authenticated` is not (the migration deliberately creates one such
-- policy on app_config).
--
-- Send the whole result back.
-- ============================================================================

WITH known(policyname) AS (
  SELECT unnest(ARRAY[
{names}
  ]::text[])
)
SELECT
  p.tablename,
  p.policyname,
  p.cmd,
  p.roles::text AS granted_to,
  CASE
    WHEN (p.qual = 'true' OR p.with_check = 'true')
         AND ('anon' = ANY(p.roles) OR 'public' = ANY(p.roles))
      THEN '*** OPEN TO ANON ***'
    WHEN (p.qual = 'true' OR p.with_check = 'true')
      THEN 'permissive (authenticated only)'
    ELSE 'scoped'
  END AS reach,
  CASE WHEN k.policyname IS NULL
       THEN '*** NOT-IN-REPO — hand created ***'
       ELSE 'in repo'
  END AS source,
  p.qual,
  p.with_check
FROM pg_policies p
LEFT JOIN known k ON k.policyname = p.policyname
WHERE p.schemaname = 'public'
ORDER BY
  (k.policyname IS NULL) DESC,
  ((p.qual = 'true' OR p.with_check = 'true')
     AND ('anon' = ANY(p.roles) OR 'public' = ANY(p.roles))) DESC,
  (p.qual = 'true' OR p.with_check = 'true') DESC,
  p.tablename,
  p.policyname;
"""


def main() -> int:
    names = known_policy_names()
    if len(names) < 20:
        print(f"FATAL: only {len(names)} policy names extracted — the parser is broken.",
              file=sys.stderr)
        return 1
    rendered = ",\n".join(
        "    " + json.dumps(n).replace('"', "'") for n in names
    )
    OUT.write_text(TEMPLATE.format(names=rendered))
    print(f"wrote {OUT.relative_to(ROOT)} with {len(names)} known policy names")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
