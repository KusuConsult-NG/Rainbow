-- ============================================================================
-- Why did an INSERT into public.alerts fail?
--
--   Failed to run sql query: ERROR:  428C9: cannot insert a non-DEFAULT value
--   into column "category"
--   DETAIL:  Column "category" is a generated column.
--
-- READ-ONLY. Safe on production. It writes nothing and locks nothing.
--
-- ONE query on purpose. The Supabase SQL editor shows only the LAST result set
-- of a multi-statement run, so a file of six SELECTs makes an operator run them
-- one at a time and report them one at a time — which is exactly what happened
-- with the board diagnostic. Everything below is a single statement returning
-- (section, name, detail), so one paste gives one table with all of it in.
--
-- ## What that error actually means
--
-- `alerts.category` is `GENERATED ALWAYS AS (split_part(type, ' - ', 1)) STORED`
-- (20261005000000), and it may not be the only generated column on the table:
-- 20260721000000 also declares `alerts.lga`, `alerts.ward` and `alerts.pu` as
-- generated mirrors of the geo_* columns, and `profiles.lga` / `profiles.ward`
-- likewise. Those were created by hand in some deployments and not others, so
-- the `generated column` rows below are the list that matters, not this comment.
--
-- 428C9 is raised at PARSE time, by the statement itself, and only ever for one
-- reason: the insert's TARGET COLUMN LIST contains a generated column. There are
-- two ways to write that, and the second is the trap. Both are shown here as
-- COMMENTS because they are the broken shapes — they are not runnable, and the
-- last two would write rows:
--
--   INSERT INTO public.alerts (id, type, category, ...) VALUES (...)   -- named
--   INSERT INTO public.alerts SELECT * FROM some_copy                 -- IMPLIED
--   INSERT INTO public.alerts VALUES ('...', '...', ...)              -- IMPLIED
--
-- An insert with NO column list targets EVERY column in ordinal order, so it
-- names `category` whether or not the author thought about it. That is why the
-- error can appear in a statement that never mentions the word.
--
-- It is NOT caused by:
--   * a BEFORE INSERT trigger that assigns to NEW.category — PostgreSQL
--     silently overwrites that with the generated value, no error (verified on
--     PostgreSQL 16)
--   * row-level security, a missing grant, or a bad value
--   * scripts/seed_demo_incidents.sql, which names all fifteen of its columns,
--     applies cleanly against the full migration chain in CI, and has never
--     named `category` in any version in git history
--
-- So the statement that failed came from somewhere outside this repository:
-- another SQL editor tab, a saved snippet, a trigger or function added in the
-- dashboard. The `trigger`, `rule` and `unsafe function` rows are there to find
-- it; if all three come back empty, it was a pasted statement and not something
-- living in the database.
--
-- ## Reading the output
--
--   generated column   a column no INSERT may name. Every insert into alerts
--                      must have an explicit column list omitting these.
--   trigger            expected: route_oversight_to_hq_trg (20261015000000) and,
--                      where 20260721000000 was applied, trg_alerts_updated_at.
--                      Anything else was created outside the migrations.
--   rule               should be none. A rule can rewrite an INSERT into a
--                      second INSERT nobody wrote.
--   unsafe function    a function whose body inserts into alerts with no column
--                      list, or names a generated column. It fails every run,
--                      not just today.
--   alerts now         what is actually in the table, which is the question
--                      underneath the error.
-- ============================================================================

WITH generated AS (
  SELECT a.attname, a.attnum,
         pg_get_expr(d.adbin, d.adrelid) AS expr
    FROM pg_attribute a
    JOIN pg_class c        ON c.oid = a.attrelid
    JOIN pg_namespace n    ON n.oid = c.relnamespace
    LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND a.attgenerated <> ''
),
triggers AS (
  SELECT t.tgname,
         CASE WHEN (t.tgtype & 2) <> 0 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
         concat_ws('/',
           CASE WHEN (t.tgtype & 4)  <> 0 THEN 'INSERT' END,
           CASE WHEN (t.tgtype & 8)  <> 0 THEN 'DELETE' END,
           CASE WHEN (t.tgtype & 16) <> 0 THEN 'UPDATE' END) AS events,
         p.proname,
         t.tgenabled
    FROM pg_trigger t
    JOIN pg_class c     ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p      ON p.oid = t.tgfoid
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND NOT t.tgisinternal
),
rules AS (
  SELECT r.rulename, pg_get_ruledef(r.oid) AS def
    FROM pg_rewrite r
    JOIN pg_class c     ON c.oid = r.ev_class
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND r.rulename <> '_RETURN'
),
unsafe AS (
  -- Two shapes: an insert into alerts with NO column list (the word after the
  -- table name is SELECT or VALUES), or one whose column list names `category`.
  SELECT n.nspname, p.proname,
         pg_get_function_identity_arguments(p.oid) AS args,
         substring(p.prosrc from '(?is)insert\s+into\s+(?:public\.)?alerts[^;]{0,100}') AS stmt
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
     AND (p.prosrc ~* 'insert\s+into\s+(?:public\.)?alerts\s+(select|values)'
          OR p.prosrc ~* 'insert\s+into\s+(?:public\.)?alerts\s*\([^)]*\bcategory\b')
),
tally AS (
  SELECT count(*) AS total,
         count(*) FILTER (WHERE description LIKE '[DEMO]%') AS demo,
         count(*) FILTER (WHERE status NOT IN
                  ('RESOLVED', 'CANCELLED', 'FALSE_REPORT')) AS still_open,
         count(DISTINCT category) AS categories,
         max(created_at) AS newest
    FROM public.alerts
)
SELECT 1 AS ord, 'generated column' AS section,
       attname AS name,
       format('ordinal %s — computed from %s', attnum, coalesce(expr, '?')) AS detail
  FROM generated
UNION ALL
SELECT 2, 'trigger', tgname,
       format('%s %s → %s()%s', timing, events, proname,
              CASE tgenabled WHEN 'D' THEN ' [DISABLED]' ELSE '' END)
  FROM triggers
UNION ALL
SELECT 3, 'rule', rulename, def FROM rules
UNION ALL
SELECT 4, 'unsafe function', format('%s.%s(%s)', nspname, proname, args), stmt
  FROM unsafe
UNION ALL
-- Said out loud rather than left as an absence: an empty section reads the same
-- as a section that did not run, and "no rules" is the useful answer here.
SELECT 5, 'nothing found', kind, 'none — so this is not where the failure lives'
  FROM (VALUES ('rule'), ('unsafe function')) AS v(kind)
 WHERE (kind = 'rule'            AND NOT EXISTS (SELECT 1 FROM rules))
    OR (kind = 'unsafe function' AND NOT EXISTS (SELECT 1 FROM unsafe))
UNION ALL
SELECT 6, 'alerts now', 'row counts',
       format('total %s / [DEMO] %s / still open %s / %s categories / newest %s',
              total, demo, still_open, categories, coalesce(newest::text, 'never'))
  FROM tally
 ORDER BY ord, name;
