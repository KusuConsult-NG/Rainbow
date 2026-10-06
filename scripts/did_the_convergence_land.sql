-- ============================================================================
-- Did 20261016, 20261017 and 20261018 actually land?
--
-- READ-ONLY. Safe on production. ONE statement, because the Supabase SQL editor
-- shows only the last result set of a multi-statement run.
--
-- WHY THIS EXISTS
--
-- Those three migrations report what they did with `RAISE NOTICE`, and the
-- Supabase SQL editor does not display NOTICE output — it shows
-- `Success. No rows returned`. So an operator pastes all three, sees three
-- identical empty results, and has no idea whether anything happened.
-- docs/APPLYING_THE_MIGRATIONS.md has said this since the dry run was written;
-- it was still overlooked when these three were handed over.
--
-- The 34-row verdict table does not close the gap either:
--
--   * it proves 20261016 landed, because its anon/public check turns PASS — the
--     telemetry policy was the only thing failing it;
--   * it cannot see 20261018 AT ALL. Not one of its 34 checks looks for the
--     absence of the five generated mirrors or the two dropped functions, and a
--     check that an object is GONE is the only evidence a drop-only migration
--     can leave;
--   * 20261017 is a no-op on a database that already has the era objects, which
--     production does, so nothing observable changes there by design.
--
-- Hence one query, three verdicts, in the terms each migration is actually
-- about.
--
-- WHAT EACH ROW MEANS IF IT FAILS
--
--   20261016  a policy in `public` still reaches anon or public. The `detail`
--             names it. Until it is fixed that policy is readable by anyone
--             holding the anon key, which is shipped in the app.
--   20261017  an era object this repository now creates is missing. A database
--             built from zero would not match production.
--   20261018  a generated mirror or dead function is still present. Not
--             dangerous in itself, but production and the harness then disagree
--             on column ordinals, which is what made one bad INSERT report
--             `lga` on one database and `category` on the other (C-4).
-- ============================================================================

WITH anon_reaching AS (
  SELECT string_agg(tablename || '.' || policyname, ', '
                    ORDER BY tablename, policyname) AS names,
         count(*) AS n
    FROM pg_policies
   WHERE schemaname = 'public'
     AND ('anon' = ANY(roles) OR 'public' = ANY(roles))
),
telemetry_policy AS (
  SELECT count(*) FILTER (
           WHERE policyname = 'telemetry_select_geo_lga_scoped') AS present,
         count(*) FILTER (
           WHERE policyname = 'telemetry_select_geo_lga_scoped'
             AND 'authenticated' = ANY(roles)) AS scoped
    FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'telemetry'
),
-- The era objects 20261017 is responsible for that SURVIVE 20261018. The five
-- mirrors it adds are dropped again by the next migration, so requiring them
-- here would make these two migrations impossible to satisfy together.
era AS (
  SELECT
    (SELECT count(*) FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname IN ('set_updated_at', 'normalise_lga')) AS fns,
    (SELECT count(*) FROM pg_trigger
      WHERE tgname = 'trg_alerts_updated_at' AND NOT tgisinternal) AS trg,
    (SELECT count(*) FROM pg_attribute a
       JOIN pg_class c     ON c.oid = a.attrelid
       JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND a.attnum > 0 AND NOT a.attisdropped
        AND ((c.relname = 'alerts'
              AND a.attname IN ('assigned_to_uid', 'post_sos_status'))
          OR (c.relname = 'profiles' AND a.attname = 'sector_id'))) AS cols
),
mirrors AS (
  SELECT string_agg(c.relname || '.' || a.attname, ', '
                    ORDER BY c.relname, a.attname) AS names,
         count(*) AS n
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND a.attnum > 0 AND NOT a.attisdropped
     AND ((c.relname = 'alerts'   AND a.attname IN ('lga', 'ward', 'pu'))
       OR (c.relname = 'profiles' AND a.attname IN ('lga', 'ward')))
),
dead_fns AS (
  SELECT string_agg(p.proname || '()', ', ' ORDER BY p.proname) AS names,
         count(*) AS n
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname IN ('is_hq_or_admin', 'is_responder')
),
-- Named so the result says which column a 428C9 error would report on THIS
-- database. The set converges; the ordinals cannot, because they are fixed when
-- a column is added.
gen AS (
  SELECT coalesce(string_agg(a.attname, ', ' ORDER BY a.attnum), '(none)') AS cols
    FROM pg_attribute a
    JOIN pg_class c     ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname = 'alerts'
     AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated <> ''
)
SELECT 1 AS ord,
       CASE WHEN ar.n = 0 AND tp.present = tp.scoped THEN 'PASS'
            ELSE '*** FAIL ***' END AS result,
       '20261016  the telemetry policy is not public' AS migration,
       CASE
         WHEN ar.n > 0 THEN 'still reaching anon/public: ' || ar.names
         WHEN tp.present = 0 THEN
           'no telemetry_select_geo_lga_scoped here (20260725 was never '
           || 'applied) — nothing to repair, which is a pass'
         ELSE 'telemetry_select_geo_lga_scoped is TO authenticated; no policy '
              || 'in public reaches anon or public'
       END AS detail
  FROM anon_reaching ar, telemetry_policy tp
UNION ALL
SELECT 2,
       CASE WHEN e.fns = 2 AND e.trg = 1 AND e.cols = 3
            THEN 'PASS' ELSE '*** FAIL ***' END,
       '20261017  the hand-applied era is in the history',
       format('functions %s/2, trigger %s/1, columns %s/3%s',
              e.fns, e.trg, e.cols,
              CASE WHEN e.fns = 2 AND e.trg = 1 AND e.cols = 3
                   THEN ' — a no-op on a database that already had them, which '
                        || 'production did'
                   ELSE ' — something this migration creates is missing' END)
  FROM era e
UNION ALL
SELECT 3,
       CASE WHEN m.n = 0 AND d.n = 0 THEN 'PASS' ELSE '*** FAIL ***' END,
       '20261018  the mirrors and two dead functions are gone',
       CASE
         WHEN m.n = 0 AND d.n = 0 THEN
           'all 5 generated mirrors and both functions are gone'
         ELSE 'still present: '
              || concat_ws(', ', nullif(m.names, ''), nullif(d.names, ''))
              || ' — this migration has not been applied'
       END
  FROM mirrors m, dead_fns d
UNION ALL
SELECT 4, 'INFO', 'alerts generated columns now', g.cols
  FROM gen g
 ORDER BY ord;
