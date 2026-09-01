#!/usr/bin/env python3
"""Generate scripts/rls_production_dryrun.sql from the real migration.

Why this is generated rather than hand-written
----------------------------------------------
The dry run wraps the migration in a transaction it always rolls back. But
20260813000000_rls_least_privilege.sql carries its OWN `BEGIN;`/`COMMIT;`, and a
nested `COMMIT` ends the OUTER transaction — so a naive paste would permanently
apply the migration while the script still printed a reassuring ROLLBACK at the
end. Against production, with no staging to catch it.

So the migration body is spliced in here with its transaction control stripped,
and the result is committed as a single file the operator pastes without editing.
A `ON COMMIT DROP` marker table guards the case anyway: if anything commits
mid-script, the marker vanishes and the script aborts before touching anything
else.

Regenerate after any change to the migration:
    python3 scripts/build_rls_dryrun.py
`scripts/check_rls_dryrun_fresh.sh` fails CI if it is stale.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIGRATION = ROOT / "supabase/migrations/20260813000000_rls_least_privilege.sql"
OUT = ROOT / "scripts/rls_production_dryrun.sql"

HEADER = """-- ============================================================================
-- PRODUCTION DRY RUN — generated file, do not edit by hand.
--   Regenerate with: python3 scripts/build_rls_dryrun.py
--
--   Paste the WHOLE of this file into the Supabase dashboard -> SQL Editor and
--   run it. It ends in ROLLBACK. Nothing it does is kept.
--
-- WHY THIS EXISTS
--
-- The migration is proven correct against a replica rebuilt from this repo's
-- migration files. That replica cannot contain policies somebody created by hand
-- in the Supabase dashboard -- and the migration drops prior policies BY EXACT
-- NAME, so a hand-made policy survives it. PostgreSQL combines PERMISSIVE
-- policies with OR, so one surviving `USING (true)` re-opens the table and the
-- migration becomes decorative. That is exactly how phase1_foundation.sql failed.
-- It is finding C-3, and with no staging project this is how you find out.
--
-- WHAT IT DOES
--
-- PostgreSQL has transactional DDL, so the policies really are created, the
-- assertions really do run against your real rows and real roles, and then all
-- of it is discarded. It INSERTS NOTHING and DELETES NOTHING. Every assertion is
-- a SELECT, or an UPDATE that is expected to be blocked.
--
-- THE ONE THING THAT COULD GO WRONG, AND THE GUARD FOR IT
--
-- The migration ships its own BEGIN/COMMIT. A nested COMMIT would end the outer
-- transaction and make this permanent. Its transaction control has been stripped
-- during generation, AND a temp marker created with ON COMMIT DROP is checked
-- afterwards: if anything committed, the marker is gone and the script aborts.
--
-- HOW TO READ THE OUTPUT
--
-- Read the NOTICE messages. `>>> SAFE TO APPLY` at the end means the migration
-- did the right thing against your real data. `>>> PROBLEM` means do not apply
-- it yet. The final SELECT must match the BEFORE numbers, proving nothing stuck.
-- ============================================================================

BEGIN;

-- Tripwire. ON COMMIT DROP means this disappears the instant anything commits.
CREATE TEMP TABLE _dryrun_marker(ok boolean) ON COMMIT DROP;
INSERT INTO _dryrun_marker VALUES (true);

-- ── 1. What is there right now ──────────────────────────────────────────────
-- Read this in the results pane. Any policy name you do not recognise from
-- supabase/migrations/ was made by hand, and is the risk this script exists for.
SELECT tablename, policyname, cmd, roles,
       CASE WHEN qual = 'true' OR with_check = 'true'
            THEN '*** WIDE OPEN ***' ELSE '' END AS warning
FROM pg_policies WHERE schemaname = 'public'
ORDER BY warning DESC, tablename, policyname;

DO $dryrun$
DECLARE n_open INT; n_total INT;
BEGIN
  SELECT count(*) INTO n_total FROM pg_policies WHERE schemaname='public';
  SELECT count(*) INTO n_open  FROM pg_policies
   WHERE schemaname='public' AND (qual='true' OR with_check='true');
  RAISE NOTICE 'BEFORE: % policies on public, % of them USING(true)/WITH CHECK(true)',
    n_total, n_open;
END $dryrun$;

-- ============================================================================
-- 2. THE MIGRATION (transaction control stripped during generation)
-- ============================================================================
"""

GUARD_AND_ASSERTIONS = """
-- ============================================================================
-- 3. TRIPWIRE — did anything commit while applying the migration?
-- ============================================================================
DO $dryrun$
BEGIN
  PERFORM 1 FROM _dryrun_marker;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ABORT: the marker table is empty — a COMMIT occurred and this is no longer a dry run.';
  END IF;
  RAISE NOTICE 'OK: still inside the dry-run transaction, nothing has been committed';
EXCEPTION WHEN undefined_table THEN
  RAISE EXCEPTION 'ABORT: the marker table is GONE — a COMMIT occurred. Changes may be PERMANENT. Stop and check pg_policies.';
END $dryrun$;

-- ============================================================================
-- 4. Assert behaviour against REAL rows and REAL roles
-- ============================================================================
DO $dryrun$
DECLARE
  n INT; n_before INT;
  cmd_id UUID; cit_id UUID;
  escalated BOOLEAN;
  problems INT := 0;
BEGIN
  -- Re-check the tripwire HERE too, not just above.
  --
  -- psql and some editors continue past a failed statement, so without this the
  -- block above could abort and this block would still run to completion and
  -- print '>>> SAFE TO APPLY' — a reassuring message produced by a script that
  -- had just permanently modified the database. Refuse to say anything at all
  -- unless we are certain we are still inside the throwaway transaction.
  BEGIN
    PERFORM 1 FROM _dryrun_marker;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ABORT: marker empty — a COMMIT occurred. Not reporting a verdict.';
    END IF;
  EXCEPTION WHEN undefined_table THEN
    RAISE EXCEPTION 'ABORT: marker GONE — a COMMIT occurred and changes may be PERMANENT. No verdict is given. Check pg_policies now.';
  END;

  SELECT id INTO cmd_id FROM public.profiles
   WHERE role IN ('HQ_COMMAND','HQ_OFFICER','ADMIN','LGA_COMMAND') LIMIT 1;
  SELECT id INTO cit_id FROM public.profiles WHERE role = 'CITIZEN' LIMIT 1;
  SELECT count(*) INTO n_before FROM public.profiles;

  RAISE NOTICE 'Live data: % profiles. command sample=%, citizen sample=%',
    n_before, coalesce(cmd_id::text,'NONE'), coalesce(cit_id::text,'NONE');

  -- ── anon must be locked out ───────────────────────────────────────────────
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    SELECT count(*) INTO n FROM public.profiles;
    IF n > 0 THEN
      RAISE NOTICE '>>> PROBLEM: anon can still read % profile rows', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: anon cannot read profiles'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon denied on profiles outright';
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.telemetry;
    IF n > 0 THEN
      RAISE NOTICE '>>> PROBLEM: anon can still read % telemetry rows (live GPS)', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: anon cannot read telemetry'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon denied on telemetry outright';
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.alerts;
    IF n > 0 THEN
      RAISE NOTICE '>>> PROBLEM: anon can still read % alert rows', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: anon cannot read alerts'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'OK: anon denied on alerts outright';
  END;

  RESET ROLE;

  -- ── command staff must NOT lose visibility ───────────────────────────────
  -- The assertion that matters most for not breaking your operation.
  IF cmd_id IS NOT NULL THEN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cmd_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n < n_before THEN
      RAISE NOTICE '>>> PROBLEM: command user sees only % of % profiles', n, n_before;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: command user still sees all % profiles', n; END IF;

    SELECT count(*) INTO n FROM public.alerts;
    RAISE NOTICE 'OK: command user sees % alerts', n;
    SELECT count(*) INTO n FROM public.telemetry;
    RAISE NOTICE 'OK: command user sees % telemetry rows', n;
    RESET ROLE;
  ELSE
    RAISE NOTICE '>>> PROBLEM: no command-role profile found — cannot prove dispatch still works';
    problems := problems + 1;
  END IF;

  -- ── a citizen sees only themselves, and cannot promote themselves ────────
  IF cit_id IS NOT NULL THEN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cit_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n <> 1 THEN
      RAISE NOTICE '>>> PROBLEM: citizen sees % profiles, expected 1', n;
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: citizen sees only their own profile'; END IF;

    -- The check C-4 depends on. Expected to be blocked.
    escalated := false;
    BEGIN
      UPDATE public.profiles SET role = 'HQ_COMMAND' WHERE id = cit_id;
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n > 0 THEN escalated := true; END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    IF escalated THEN
      RAISE NOTICE '>>> PROBLEM: a citizen escalated their own role to HQ_COMMAND';
      problems := problems + 1;
    ELSE RAISE NOTICE 'OK: self role escalation blocked'; END IF;

    RESET ROLE;
  ELSE
    RAISE NOTICE 'note: no CITIZEN profile found — citizen scoping not exercised';
  END IF;

  RESET ROLE;

  RAISE NOTICE '=========================================';
  IF problems = 0 THEN
    RAISE NOTICE '>>> SAFE TO APPLY — 0 problems found';
  ELSE
    RAISE NOTICE '>>> DO NOT APPLY — % problem(s) above', problems;
  END IF;
  RAISE NOTICE '=========================================';
END $dryrun$;

-- ============================================================================
-- 5. Throw all of it away
-- ============================================================================
ROLLBACK;

-- Must match the BEFORE numbers above. If it does not, something persisted.
SELECT count(*) FILTER (WHERE qual='true' OR with_check='true') AS still_wide_open,
       count(*) AS total_policies
FROM pg_policies WHERE schemaname='public';
"""


def strip_transaction_control(sql: str) -> str:
    """Remove top-level BEGIN;/COMMIT; without touching PL/pgSQL BEGIN...END blocks.

    Only lines that are exactly `BEGIN;` or `COMMIT;` at column 0 are stripped.
    A PL/pgSQL block's BEGIN is indented or followed by declarations, and its
    terminator is `END $tag$;` — neither matches.
    """
    out, removed = [], 0
    for line in sql.splitlines():
        if re.fullmatch(r"(BEGIN|COMMIT|START TRANSACTION)\s*;\s*", line):
            out.append(f"-- [dry run] stripped: {line.strip()}")
            removed += 1
        else:
            out.append(line)
    if removed == 0:
        print("WARNING: no transaction control found to strip — has the migration changed?",
              file=sys.stderr)
    else:
        print(f"stripped {removed} top-level transaction statement(s)")
    return "\n".join(out)


def main() -> int:
    migration = MIGRATION.read_text()
    body = strip_transaction_control(migration)

    # Refuse to generate something that would commit against production.
    for line in body.splitlines():
        if re.fullmatch(r"(BEGIN|COMMIT|START TRANSACTION)\s*;\s*", line):
            print("FATAL: transaction control survived stripping.", file=sys.stderr)
            return 1

    OUT.write_text(HEADER + body + GUARD_AND_ASSERTIONS)
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.read_text().count(chr(10))} lines)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
