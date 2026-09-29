-- ════════════════════════════════════════════════════════════════════════════
-- Why does the incident board show nothing?
-- ════════════════════════════════════════════════════════════════════════════
--
-- Paste the queries below into the Supabase SQL editor, one section at a time.
-- The whole file only READS — there is no INSERT, UPDATE, DELETE or DDL
-- anywhere in it — so it is safe to run against production.
--
-- No psql meta-commands (\echo, \set): the web SQL editor runs plain SQL only
-- and would reject them.
--
-- The SQL editor runs as an owner role that BYPASSES row-level security, which
-- is what makes it useful here. It can see rows your console account may not,
-- and the difference between those two answers is the diagnosis.
--
-- Section 3 calls public.geo_key(), added in
-- 20261009000000_ward_names_compared_by_key.sql. If it errors with "function
-- geo_key does not exist", apply that migration first — the console needs it
-- regardless.
--
-- Read the sections in order. The first one whose answer is wrong is the cause;
-- the ones after it will look wrong as a consequence.


-- ─── 1. Are the incidents actually in the database? ─────────────────────────
--
-- total = 0        nothing is seeded, or the console points at a different
--                  Supabase project. Check NEXT_PUBLIC_SUPABASE_URL against
--                  this project's URL before anything else.
-- demo  = 0        scripts/seed_demo_incidents.sql has not run here.

SELECT count(*)                                                      AS total,
       count(*) FILTER (WHERE description LIKE '[DEMO]%')            AS demo,
       count(*) FILTER (WHERE created_at > now() - INTERVAL '1 day')  AS last_24h,
       min(created_at)                                               AS oldest,
       max(created_at)                                               AS newest
  FROM public.alerts;


-- ─── 2. Who is your console account? ───────────────────────────────────────
--
-- commands_whole_state must be true for an account meant to see all of
-- Plateau. It is true ONLY for role HQ_COMMAND, HQ_OFFICER or ADMIN.
--
-- If it is false and geo_lga is NULL, that account sees NOTHING except
-- incidents it reported or was assigned to — deliberately. profiles.geo_lga is
-- self-writable, so a blank posting has to be the weakest posting and never the
-- widest. See 20261006000000_alerts_scoped_to_posting.sql.
--
-- Replace the ILIKE pattern with your console sign-in email.

SELECT p.email,
       p.role,
       p.geo_lga,
       p.geo_ward,
       p.geo_pu,
       upper(coalesce(p.role, '')) IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN')
         AS commands_whole_state
  FROM public.profiles p
 WHERE p.email ILIKE '%'          -- ← e.g. '%kusuconsult%'
 ORDER BY commands_whole_state DESC, p.role
 LIMIT 20;


-- ─── 3. How many incidents would row-level security admit, per account? ─────
--
-- The rule from alert_is_ours(), written out inline and evaluated PER PROFILE.
--
-- It cannot call alert_is_ours() or alert_in_my_area() directly: those read
-- auth.uid(), which is NULL in the SQL editor, so they would return the same
-- answer for every row here and the column would be meaningless. This restates
-- the same predicate against p instead of against the current session.
--
-- An account showing 0 will see an empty board however the console is written.
-- The refusal is in the database, not in the browser.

SELECT p.email,
       p.role,
       p.geo_lga,
       p.geo_ward,
       (SELECT count(*)
          FROM public.alerts a
         WHERE
           -- HQ and administrators: the whole state.
           upper(coalesce(p.role, '')) IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN')
           -- The reporter, the lead, and every officer on the dispatched team.
           OR a.reported_by = p.id
           OR a.assigned_to = p.id
           OR p.id::text = ANY (coalesce(a.assigned_responders, '{}'::text[]))
           -- Staff, within their command. A liaison is any role ending in
           -- _LIAISON (POLICE_LIAISON, ARMY_LIAISON, …) and is NOT staff for
           -- this purpose: they see only what was escalated to their agency.
           -- Listing a fixed 'AGENCY_LIAISON' here instead would report a
           -- police liaison as seeing their whole LGA, which they cannot.
           OR (upper(coalesce(p.role, '')) <> 'CITIZEN'
               AND coalesce(p.role, '') NOT LIKE '%\_LIAISON'
               AND CASE
                 -- An unlocated incident is visible to all staff: an emergency
                 -- nobody can see is worse than one seen too widely.
                 WHEN public.geo_key(a.geo_lga) IS NULL THEN true
                 -- No posting, no area.
                 WHEN public.geo_key(p.geo_lga) IS NULL THEN false
                 WHEN upper(coalesce(p.role, '')) LIKE 'WARD%' THEN
                   public.geo_key(a.geo_lga) = public.geo_key(p.geo_lga)
                   AND public.geo_key(p.geo_ward) IS NOT NULL
                   AND public.geo_key(a.geo_ward) = public.geo_key(p.geo_ward)
                 WHEN upper(coalesce(p.role, '')) LIKE 'UNIT%'
                   OR upper(coalesce(p.role, '')) LIKE 'POLLING%' THEN
                   public.geo_key(a.geo_lga) = public.geo_key(p.geo_lga)
                   AND public.geo_key(p.geo_pu) IS NOT NULL
                   AND public.geo_key(a.geo_pu) = public.geo_key(p.geo_pu)
                 ELSE public.geo_key(a.geo_lga) = public.geo_key(p.geo_lga)
               END)
       ) AS would_see
  FROM public.profiles p
 WHERE upper(coalesce(p.role, '')) <> 'CITIZEN'
 ORDER BY would_see DESC, p.role
 LIMIT 30;


-- ─── 4. Is the geography on the rows selectable in the console? ─────────────
--
-- The console builds its ward and polling-unit filters from the tactical map.
-- A row whose geo_ward is not in that map can be FILED but not FILTERED, and a
-- ward officer posted to the map's spelling is refused it.
--
-- Cross-check these names against lib/core/constants/tactical_mapping.dart, or
-- run: python3 scripts/sync_tactical_map.py --check

SELECT coalesce(geo_lga,  '(none)') AS lga,
       coalesce(geo_ward, '(none)') AS ward,
       count(*)                     AS incidents
  FROM public.alerts
 GROUP BY 1, 2
 ORDER BY 3 DESC, 1, 2
 LIMIT 40;


-- ─── 5. Is anything else quietly empty? ────────────────────────────────────
--
-- A large unacknowledged count with an empty outbox means the escalation job is
-- not running. A large outbox_pending means the drain worker is not.
--
-- There is no failed_at column: a failure sets last_error and pushes
-- next_attempt_at forward, because a notice that could not be delivered is
-- still owed and has to be tried again. outbox_erroring counts rows that have
-- been attempted and are still undelivered.

SELECT (SELECT count(*) FROM public.alerts
          WHERE status NOT IN ('RESOLVED', 'CLOSED'))               AS open_incidents,
       (SELECT count(*) FROM public.alerts
          WHERE status NOT IN ('RESOLVED', 'CLOSED')
            AND acknowledged_at IS NULL)                            AS unacknowledged,
       (SELECT count(*) FROM public.notification_outbox)            AS outbox_rows,
       (SELECT count(*) FROM public.notification_outbox
          WHERE delivered_at IS NULL)                               AS outbox_pending,
       (SELECT count(*) FROM public.notification_outbox
          WHERE delivered_at IS NULL AND attempts > 0)              AS outbox_erroring,
       (SELECT max(attempts) FROM public.notification_outbox
          WHERE delivered_at IS NULL)                               AS worst_attempts,
       (SELECT last_error FROM public.notification_outbox
          WHERE delivered_at IS NULL AND last_error IS NOT NULL
          ORDER BY id DESC LIMIT 1)                                 AS newest_error;


-- ─── What the answers mean ─────────────────────────────────────────────────
--
--   1 shows total 0        Nothing is seeded here, or the console is pointed at
--                          a different project.
--   2 shows false + NULL   That account has no posting and commands nothing.
--                          Give it a geo_lga, or set role = 'HQ_COMMAND'.
--   3 shows 0 for you      Row-level security is refusing the read. The console
--                          now shows FEED UNAVAILABLE with the error, instead of
--                          claiming ALL SECTORS CLEAR.
--   4 lists unknown wards  The rows are visible but the ward filter cannot
--                          select them.
--   1 and 3 both healthy   The read is fine and a filter is hiding them. The
--                          board now says NO MATCH FOR THESE FILTERS and names
--                          how many are being withheld.
