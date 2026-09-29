-- ============================================================================
-- Why did an INSERT into public.alerts fail?
--
--   Failed to run sql query: ERROR:  428C9: cannot insert a non-DEFAULT value
--   into column "category"
--   DETAIL:  Column "category" is a generated column.
--
-- READ-ONLY. Safe on production. It writes nothing and locks nothing.
-- Paste the whole file into the Supabase SQL editor and send back the output.
--
-- ## What that error actually means
--
-- `alerts.category` is `GENERATED ALWAYS AS (split_part(type, ' - ', 1)) STORED`
-- (20261005000000), and it is not necessarily the only generated column on the
-- table: 20260721000000 also declares `alerts.lga`, `alerts.ward` and
-- `alerts.pu` as generated mirrors of the geo_* columns, and `profiles.lga` /
-- `profiles.ward` likewise. Section 1 prints what YOUR database has, which is
-- the list that matters — the agency-era columns were created by hand in some
-- deployments and not others.
--
-- 428C9 is raised at PARSE time, by the statement itself, and only ever for one
-- reason: the insert's TARGET COLUMN LIST contains a generated column. There are
-- exactly two ways to write that, and the second one is the trap:
--
--   INSERT INTO public.alerts (id, type, category, ...) VALUES (...)   -- named
--   INSERT INTO public.alerts SELECT * FROM somewhere                 -- IMPLIED
--   INSERT INTO public.alerts VALUES ('...', '...', ...)              -- IMPLIED
--
-- An insert with NO column list targets EVERY column in ordinal order, so it
-- names `category` whether or not the author thought about it. That is why the
-- error can appear in a statement that never mentions the word.
--
-- It is NOT caused by:
--   * a BEFORE INSERT trigger that assigns to NEW.category — Postgres silently
--     overwrites that with the generated value, no error (verified on PG 16)
--   * row-level security, a missing grant, or a bad value
--   * anything in scripts/seed_demo_incidents.sql, which names all fifteen of
--     its columns and is applied against a fully-migrated PostgreSQL 16 in CI
--
-- So the statement that failed came from somewhere that is not this repository:
-- another SQL editor tab, a saved snippet, a dashboard-created trigger, or a
-- function added by hand. Sections 2–4 are here to find it.
-- ============================================================================

-- ── 1. Which columns may never be named in an INSERT ────────────────────────
--
-- `attgenerated = 's'` is a STORED generated column. Anything listed here must
-- be left out of every insert, and every insert must have a column list.
SELECT 'generated columns' AS section,
       a.attname          AS column_name,
       a.attnum           AS ordinal,
       pg_get_expr(d.adbin, d.adrelid) AS generated_from
  FROM pg_attribute a
  JOIN pg_class c      ON c.oid = a.attrelid
  JOIN pg_namespace n  ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
 WHERE n.nspname = 'public'
   AND c.relname = 'alerts'
   AND a.attgenerated <> ''
 ORDER BY a.attnum;

-- ── 2. Every trigger on public.alerts, including ones added by hand ─────────
--
-- Two are expected, and no more:
--   trg_alerts_updated_at    BEFORE UPDATE   (20260721000000)
--   route_oversight_to_hq_trg BEFORE INSERT  (20261015000000)
-- Anything else was created outside the migration history and is worth reading.
SELECT 'triggers on alerts' AS section,
       t.tgname            AS trigger_name,
       CASE WHEN (t.tgtype & 2) <> 0 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
       concat_ws(' ',
         CASE WHEN (t.tgtype & 4)  <> 0 THEN 'INSERT' END,
         CASE WHEN (t.tgtype & 8)  <> 0 THEN 'DELETE' END,
         CASE WHEN (t.tgtype & 16) <> 0 THEN 'UPDATE' END) AS events,
       p.proname           AS function_name,
       t.tgenabled         AS enabled
  FROM pg_trigger t
  JOIN pg_class c     ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_proc p      ON p.oid = t.tgfoid
 WHERE n.nspname = 'public'
   AND c.relname = 'alerts'
   AND NOT t.tgisinternal
 ORDER BY t.tgname;

-- ── 3. Rules on public.alerts ──────────────────────────────────────────────
--
-- A rule can rewrite an INSERT into a second INSERT you never wrote. There
-- should be none at all beyond the internal `_RETURN`.
SELECT 'rules on alerts' AS section,
       r.rulename,
       pg_get_ruledef(r.oid) AS definition
  FROM pg_rewrite r
  JOIN pg_class c     ON c.oid = r.ev_class
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname = 'alerts'
   AND r.rulename <> '_RETURN';

-- ── 4. Any function anywhere that inserts into alerts unsafely ─────────────
--
-- Matches two shapes:
--   a) an insert into alerts with NO column list — `INSERT INTO alerts SELECT`
--      or `INSERT INTO alerts VALUES`, which targets `category` implicitly
--   b) an insert into alerts that names `category` explicitly
--
-- Both are the defect; a function found here will fail every time it runs, not
-- just today.
SELECT 'unsafe insert in a function' AS section,
       n.nspname AS schema,
       p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS args,
       substring(p.prosrc from '(?is)insert\s+into\s+(?:public\.)?alerts[^;]{0,120}') AS the_statement
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
   AND p.prosrc ~* 'insert\s+into\s+(?:public\.)?alerts\s*(select|values|\()'
   AND (
     -- no column list: the word after the table name is SELECT or VALUES
     p.prosrc ~* 'insert\s+into\s+(?:public\.)?alerts\s+(select|values)'
     -- or the column list contains `category`
     OR p.prosrc ~* 'insert\s+into\s+(?:public\.)?alerts\s*\([^)]*\bcategory\b'
   )
 ORDER BY n.nspname, p.proname;

-- ── 5. The column list in ordinal order ────────────────────────────────────
--
-- If a statement is doing `INSERT INTO public.alerts SELECT * FROM <copy>`,
-- this is the order it is trying to fill, and the first row marked GENERATED
-- below is the one the error names.
-- The remedy is always the same: name the columns, and leave the generated ones
-- out. There is no INSERT syntax that skips a generated column positionally.
SELECT 'alerts columns in order' AS section,
       a.attnum AS ordinal,
       a.attname AS column_name,
       format_type(a.atttypid, a.atttypmod) AS type,
       CASE a.attgenerated WHEN 's' THEN 'GENERATED — never name it' ELSE '' END AS note
  FROM pg_attribute a
  JOIN pg_class c     ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname = 'alerts'
   AND a.attnum > 0
   AND NOT a.attisdropped
 ORDER BY a.attnum;

-- ── 6. Did the re-seed land, or is the board still empty? ──────────────────
--
-- Answers the question underneath the error: after the delete and the failed
-- insert, what is actually in the table.
SELECT 'what is in alerts now' AS section,
       count(*)                                                   AS total,
       count(*) FILTER (WHERE description LIKE '[DEMO]%')          AS demo_rows,
       count(*) FILTER (WHERE status NOT IN
                          ('RESOLVED','CANCELLED','FALSE_REPORT')) AS open_rows,
       count(DISTINCT category)                                    AS categories,
       min(created_at)                                             AS oldest,
       max(created_at)                                             AS newest
  FROM public.alerts;
