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
--   run it. It ends by raising an error ON PURPOSE — that error is the
--   result. Nothing it does is kept.
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
-- **THIS SCRIPT ENDS IN AN ERROR, AND THAT IS THE SUCCESS CASE.** The findings
-- are the error message. Read it; the verdict is on its first line:
--
--   ===== RLS DRY RUN — >>> SAFE TO APPLY =====   the migration did the right
--                                                 thing on your data
--   ===== RLS DRY RUN — >>> DO NOT APPLY =====    PROBLEM lines follow — send them
--
-- WHY AN ERROR AND NOT A RESULT SET
--
-- The first version returned the findings as rows and ended with ROLLBACK. Run
-- against the real database it came back as three column headers and ZERO ROWS:
-- no error, no findings, nothing to act on — indistinguishable from "all clear"
-- on a script whose entire job is to answer "is this safe to apply". Two causes,
-- both fixed here:
--
--   1. A result set is transactional. If the client has not materialised the
--      rows before the ROLLBACK lands, there is nothing left to hand back. An
--      error message is delivered out of band and cannot be rolled back.
--   2. Any unhandled error inside the script aborts the whole transaction and
--      takes every finding with it. Reproduced deliberately: with `authenticated`
--      lacking SELECT on `profiles`, the old script emitted `ERROR: permission
--      denied` and nothing else. The assertion sections are now individually
--      guarded, so a failure is RECORDED as a PROBLEM and the rest still runs.
--
-- Raising also makes the rollback intrinsic rather than a trailing statement
-- that has to survive whatever the client does with the batch: the transaction
-- is aborted by the RAISE itself, so this cannot commit even in principle.
--
-- To confirm nothing persisted afterwards, re-run scripts/rls_inventory.sql and
-- check the policy count is unchanged.
--
-- RUN scripts/rls_inventory.sql FIRST. It is read-only and lists every policy
-- this repository does not create — the ones this migration will not drop.
-- ============================================================================

BEGIN;

-- Tripwire. ON COMMIT DROP means this disappears the instant anything commits.
CREATE TEMP TABLE _dryrun_marker(ok boolean) ON COMMIT DROP;
INSERT INTO _dryrun_marker VALUES (true);

-- Findings are collected as ROWS, not RAISE NOTICE. The Supabase SQL Editor does
-- not surface notices at all — the first version of this script reported its
-- entire verdict through NOTICE and the operator saw none of it. The last
-- row-returning statement is what the editor displays, so that is the verdict.
CREATE TEMP TABLE _findings(
  seq    serial,
  status text,
  check_ text,
  detail text
) ON COMMIT DROP;

-- The assertions impersonate anon and authenticated via SET LOCAL ROLE, and those
-- roles cannot write to a table owned by the session user. Without these grants
-- the first anon assertion dies with "permission denied for table _findings" and
-- the whole transaction aborts. It is a temp table inside a transaction that is
-- always rolled back, so granting broadly here costs nothing.
GRANT ALL ON _findings TO PUBLIC;
GRANT ALL ON SEQUENCE _findings_seq_seq TO PUBLIC;

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
  INSERT INTO _findings(status, check_, detail) VALUES ('BEFORE', 'policies on public', n_total || ' total, ' || n_open || ' with USING(true)/WITH CHECK(true)');
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
  INSERT INTO _findings(status, check_, detail) VALUES ('OK', 'still inside the dry-run transaction', 'nothing committed');
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

  INSERT INTO _findings(status, check_, detail) VALUES ('INFO', 'live data', n_before || ' profiles; command sample=' || coalesce(cmd_id::text,'NONE') || '; citizen sample=' || coalesce(cit_id::text,'NONE'));

  -- ── anon must be locked out ───────────────────────────────────────────────
  SET LOCAL ROLE anon;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', 'anon', true);

  BEGIN
    SELECT count(*) INTO n FROM public.profiles;
    IF n > 0 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM', 'anon reads profiles', n || ' rows visible');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon cannot read profiles',''); END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon denied on profiles','privilege denied');
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.telemetry;
    IF n > 0 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','anon reads telemetry (live GPS)', n || ' rows visible');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon cannot read telemetry',''); END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon denied on telemetry','privilege denied');
  END;

  BEGIN
    SELECT count(*) INTO n FROM public.alerts;
    IF n > 0 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','anon reads alerts', n || ' rows visible');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon cannot read alerts',''); END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','anon denied on alerts','privilege denied');
  END;

  RESET ROLE;

  -- ── command staff must NOT lose visibility ───────────────────────────────
  -- The assertion that matters most for not breaking your operation.
  IF cmd_id IS NOT NULL THEN
   -- Guarded. An unhandled error anywhere in here aborts the WHOLE transaction,
   -- and every finding gathered so far dies with it — the operator then gets an
   -- empty result and no way to tell "clean" from "the script fell over".
   -- Recording the failure as a finding is strictly better than losing all of them.
   BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cmd_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n < n_before THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','command user lost visibility', n || ' of ' || n_before || ' profiles');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','command user sees all profiles', n || ' profiles'); END IF;

    SELECT count(*) INTO n FROM public.alerts;
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','command user sees alerts', n || ' alerts');
    SELECT count(*) INTO n FROM public.telemetry;
    INSERT INTO _findings(status, check_, detail) VALUES ('OK','command user sees telemetry', n || ' rows');
    RESET ROLE;
   EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    INSERT INTO _findings(status, check_, detail)
      VALUES ('PROBLEM','command visibility check could not run', SQLERRM);
    problems := problems + 1;
   END;
  ELSE
    INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','no command-role profile found','cannot prove dispatch still works');
    problems := problems + 1;
  END IF;

  -- ── a citizen sees only themselves, and cannot promote themselves ────────
  IF cit_id IS NOT NULL THEN
   BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
    PERFORM set_config('request.jwt.claim.sub', cit_id::text, true);

    SELECT count(*) INTO n FROM public.profiles;
    IF n <> 1 THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','citizen sees too many profiles', n || ', expected 1');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','citizen sees only their own profile',''); END IF;

    -- The check C-4 depends on. Expected to be blocked.
    escalated := false;
    BEGIN
      UPDATE public.profiles SET role = 'HQ_COMMAND' WHERE id = cit_id;
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n > 0 THEN escalated := true; END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    IF escalated THEN
      INSERT INTO _findings(status, check_, detail) VALUES ('PROBLEM','citizen escalated to HQ_COMMAND','privilege escalation NOT blocked');
      problems := problems + 1;
    ELSE INSERT INTO _findings(status, check_, detail) VALUES ('OK','self role escalation blocked',''); END IF;

    RESET ROLE;
   EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    INSERT INTO _findings(status, check_, detail)
      VALUES ('PROBLEM','citizen scoping check could not run', SQLERRM);
    problems := problems + 1;
   END;
  ELSE
    INSERT INTO _findings(status, check_, detail) VALUES ('INFO','no CITIZEN profile found','citizen scoping not exercised');
  END IF;

  RESET ROLE;

  IF problems = 0 THEN
    INSERT INTO _findings(status, check_, detail) VALUES ('VERDICT','>>> SAFE TO APPLY','0 problems found');
  ELSE
    INSERT INTO _findings(status, check_, detail) VALUES ('VERDICT','>>> DO NOT APPLY', problems || ' problem(s) above');
  END IF;
END $dryrun$;

-- ============================================================================
-- 5. THE VERDICT — delivered as an ERROR, on purpose.
--
-- This used to be `SELECT ... FROM _findings;` followed by `ROLLBACK;`, and it
-- came back from the Supabase SQL Editor as the three column headers with ZERO
-- ROWS — no error, no findings, nothing to act on. A result set is transactional:
-- if the client has not materialised the rows by the time the ROLLBACK lands,
-- there is nothing left to hand back, and the operator is told nothing at all.
-- On a script whose whole job is to answer "is this safe to apply", silence is
-- the worst possible output — it is indistinguishable from "no problems".
--
-- An error message is delivered out of band and cannot be rolled back. Raising
-- one also makes the rollback intrinsic rather than a trailing statement that
-- has to survive whatever the client does with the batch: the transaction is
-- aborted by the RAISE itself, so this script cannot commit even in principle.
--
-- So: SEEING AN ERROR HERE IS THE SUCCESS CASE. Read the message.
-- The verdict is on its first line, so it survives any truncation.
-- ============================================================================
DO $emit$
DECLARE
  verdict text;
  body    text;
BEGIN
  SELECT detail INTO verdict FROM _findings WHERE status = 'VERDICT' LIMIT 1;

  SELECT string_agg(format('%s | %s | %s', status, check_, detail), chr(10) ORDER BY seq)
    INTO body
    FROM _findings
   WHERE status <> 'VERDICT';

  RAISE EXCEPTION E'\n\n===== RLS DRY RUN — % =====\n%\n\n(This error IS the result. Nothing was kept.)',
    COALESCE((SELECT check_ FROM _findings WHERE status = 'VERDICT' LIMIT 1), '>>> NO VERDICT — the checks did not run'),
    COALESCE(body, '(no findings recorded)')
    USING ERRCODE = 'raise_exception';
END $emit$;

-- ============================================================================
-- 6. Belt and braces. The RAISE above has already aborted the transaction, so
--    this is a no-op that exists only for the case where someone edits the
--    emit block out. To confirm nothing persisted, re-run
--    scripts/rls_inventory.sql and check the row count is unchanged.
-- ============================================================================
ROLLBACK;
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
