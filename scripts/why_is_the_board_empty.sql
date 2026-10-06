-- ════════════════════════════════════════════════════════════════════════════
-- Why does the incident board show nothing?
-- ════════════════════════════════════════════════════════════════════════════
--
-- Paste the WHOLE file into the Supabase SQL editor and run it once.
--
-- ONE statement, on purpose. It used to be six, and the Supabase editor shows
-- only the LAST result set of a multi-statement run — so an operator ran it a
-- section at a time and reported back one table per message, and on one of
-- those runs a bare "0 rows" came back with nothing to say which section had
-- produced it. Everything is one query returning (section, name, detail) now.
--
-- READ-ONLY. There is no INSERT, UPDATE, DELETE or DDL anywhere in it, so it is
-- safe against production. No psql meta-commands either (\echo, \set): the web
-- editor runs plain SQL only and would reject them.
--
-- The editor runs as an owner role that BYPASSES row-level security, which is
-- what makes this useful: it sees rows your console account may not, and the
-- difference between those two answers is the diagnosis. That is what the
-- `would see` section computes.
--
-- ## Two migrations it depends on
--
-- Being one statement has one cost: a missing dependency fails the whole thing
-- rather than one section. If you get either of these, apply that migration —
-- the console needs it regardless:
--
--   function public.geo_key does not exist
--       20261009000000_ward_names_compared_by_key.sql
--   relation "public.notification_outbox" does not exist
--       20261007000000_notification_outbox.sql
--
-- ## Reading the output
--
-- Start at the bottom. The `verdict` rows name the first thing that is wrong,
-- computed rather than left for you to work out by eye — which is what the
-- six-section version asked for and what nobody does at two in the morning.
-- Then read upward for the detail behind it.
-- ════════════════════════════════════════════════════════════════════════════

WITH headline AS (
  SELECT
    (SELECT count(*) FROM public.alerts)                                AS alerts_total,
    (SELECT count(*) FROM public.profiles)                              AS profiles_total,
    (SELECT count(*) FROM public.profiles
       WHERE upper(coalesce(role, '')) <> 'CITIZEN')                    AS staff_profiles,
    (SELECT count(*) FROM public.profiles
       WHERE upper(coalesce(role, ''))
             IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN'))                  AS whole_state_accounts,
    (SELECT count(*) FROM public.profiles
       WHERE upper(coalesce(role, '')) <> 'CITIZEN'
         AND nullif(trim(coalesce(geo_lga, '')), '') IS NULL)           AS staff_with_no_posting,
    (SELECT count(*) FROM auth.users)                                   AS auth_users,
    (SELECT count(*) FROM auth.users u
       WHERE NOT EXISTS (SELECT 1 FROM public.profiles p
                          WHERE p.id = u.id))                           AS users_with_no_profile
),
incidents AS (
  SELECT count(*)                                                       AS total,
         count(*) FILTER (WHERE description LIKE '[DEMO]%')             AS demo,
         count(*) FILTER (WHERE created_at > now() - INTERVAL '1 day')  AS last_24h,
         min(created_at)                                                AS oldest,
         max(created_at)                                                AS newest
    FROM public.alerts
),
-- The rule from alert_is_ours(), written out inline and evaluated PER PROFILE.
--
-- It cannot call alert_is_ours() or alert_in_my_area() directly: those read
-- auth.uid(), which is NULL in the SQL editor, so they would return the same
-- answer for every row and the column would be meaningless. This restates the
-- same predicate against p instead of against the current session.
--
-- An account showing 0 will see an empty board however the console is written.
-- The refusal is in the database, not in the browser.
visibility AS (
  SELECT p.id,
         p.email,
         p.role,
         p.geo_lga,
         p.geo_ward,
         p.geo_pu,
         upper(coalesce(p.role, '')) IN ('HQ_COMMAND', 'HQ_OFFICER', 'ADMIN')
           AS commands_whole_state,
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
                   -- An unlocated incident is visible to all staff: an
                   -- emergency nobody can see is worse than one seen too widely.
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
),
geography AS (
  SELECT coalesce(geo_lga,  '(none)') AS lga,
         coalesce(geo_ward, '(none)') AS ward,
         count(*)                     AS incidents
    FROM public.alerts
   GROUP BY 1, 2
),
pipeline AS (
  SELECT
    (SELECT count(*) FROM public.alerts
       WHERE status NOT IN ('RESOLVED', 'CLOSED'))                      AS open_incidents,
    (SELECT count(*) FROM public.alerts
       WHERE status NOT IN ('RESOLVED', 'CLOSED')
         AND acknowledged_at IS NULL)                                   AS unacknowledged,
    (SELECT count(*) FROM public.notification_outbox)                   AS outbox_rows,
    (SELECT count(*) FROM public.notification_outbox
       WHERE delivered_at IS NULL)                                      AS outbox_pending,
    (SELECT count(*) FROM public.notification_outbox
       WHERE delivered_at IS NULL AND attempts > 0)                     AS outbox_erroring,
    (SELECT max(attempts) FROM public.notification_outbox
       WHERE delivered_at IS NULL)                                      AS worst_attempts,
    (SELECT last_error FROM public.notification_outbox
       WHERE delivered_at IS NULL AND last_error IS NOT NULL
       ORDER BY id DESC LIMIT 1)                                        AS newest_error
)

-- ─── 1. The counts that usually settle it ───────────────────────────────────
SELECT 1 AS ord, 'headline' AS section, 'alerts_total' AS name,
       format('%s%s', h.alerts_total,
         CASE WHEN h.alerts_total = 0
           THEN ' — nothing is here. The console may be pointed at a different Supabase project entirely'
           ELSE '' END) AS detail
  FROM headline h
UNION ALL
SELECT 1, 'headline', 'staff_profiles',
       format('%s%s', h.staff_profiles,
         CASE WHEN h.staff_profiles = 0
           THEN ' — NOBODY has a staff role. Every account is a CITIZEN, so each sees only the incidents it reported, and every board is empty and always will be'
           ELSE '' END)
  FROM headline h
UNION ALL
SELECT 1, 'headline', 'whole_state_accounts',
       format('%s%s', h.whole_state_accounts,
         CASE WHEN h.whole_state_accounts = 0
           THEN ' — no account can see all of Plateau. That is HQ_COMMAND, HQ_OFFICER or ADMIN and nothing else — not SUPER_ADMIN, not STATE_COMMAND'
           ELSE '' END)
  FROM headline h
UNION ALL
SELECT 1, 'headline', 'staff_with_no_posting',
       format('%s%s', h.staff_with_no_posting,
         CASE WHEN h.staff_with_no_posting > 0
           THEN ' — staff with a blank geo_lga. A blank posting is deliberately the WEAKEST, never the widest: profiles.geo_lga is self-writable, so blank-means-everywhere would let a ward commander take the state'
           ELSE '' END)
  FROM headline h
UNION ALL
SELECT 1, 'headline', 'users_with_no_profile',
       format('%s%s', h.users_with_no_profile,
         CASE WHEN h.users_with_no_profile > 0
           THEN ' — someone can sign in but has no profiles row. auth.users is the credential; public.profiles carries the role and posting, and RLS reads only the latter. Authenticated, authorised for nothing'
           ELSE '' END)
  FROM headline h
UNION ALL
SELECT 1, 'headline', 'profiles / auth users',
       format('%s profiles, %s auth users', h.profiles_total, h.auth_users)
  FROM headline h

-- ─── 2. Are the incidents actually in the database? ─────────────────────────
UNION ALL
SELECT 2, 'incidents', 'counts',
       format('total %s / [DEMO] %s / last 24h %s', i.total, i.demo, i.last_24h)
  FROM incidents i
UNION ALL
SELECT 2, 'incidents', 'span',
       format('oldest %s / newest %s',
              coalesce(i.oldest::text, 'never'), coalesce(i.newest::text, 'never'))
  FROM incidents i

-- ─── 3. What each account would be allowed to see ───────────────────────────
UNION ALL
SELECT 3, 'would see',
       coalesce(v.email, v.id::text),
       format('%s of %s incidents — role %s, posting %s/%s/%s%s',
              v.would_see,
              (SELECT total FROM incidents),
              coalesce(v.role, '(none)'),
              coalesce(nullif(v.geo_lga, ''), '—'),
              coalesce(nullif(v.geo_ward, ''), '—'),
              coalesce(nullif(v.geo_pu, ''), '—'),
              CASE WHEN v.commands_whole_state THEN ', commands the whole state' ELSE '' END)
  FROM visibility v
 WHERE upper(coalesce(v.role, '')) <> 'CITIZEN'

-- ─── 4. Is the geography selectable in the console? ─────────────────────────
--
-- The console builds its ward and polling-unit filters from the tactical map. A
-- row whose geo_ward is not in that map can be FILED but not FILTERED, and a
-- ward officer posted to the map's spelling is refused it. Cross-check these
-- names with: python3 scripts/sync_tactical_map.py --check
UNION ALL
SELECT 4, 'geography', format('%s / %s', g.lga, g.ward),
       format('%s incident(s)', g.incidents)
  FROM geography g

-- ─── 5. Is anything else quietly empty? ─────────────────────────────────────
UNION ALL
SELECT 5, 'pipeline', 'incidents',
       format('%s open, %s unacknowledged', p.open_incidents, p.unacknowledged)
  FROM pipeline p
UNION ALL
SELECT 5, 'pipeline', 'outbox',
       format('%s rows / %s pending / %s erroring / worst attempts %s',
              p.outbox_rows, p.outbox_pending, p.outbox_erroring,
              coalesce(p.worst_attempts::text, '0'))
  FROM pipeline p
UNION ALL
SELECT 5, 'pipeline', 'newest outbox error',
       coalesce(p.newest_error, '(none)')
  FROM pipeline p

-- ─── 6. The verdict, computed ───────────────────────────────────────────────
--
-- The six-section version ended with a table of "if section N says X then Y"
-- and left the operator to walk it. This evaluates the same rules in the same
-- order and names the first one that fires. More than one row here means more
-- than one thing is wrong; the first is the one to fix.
UNION ALL
-- The rank goes in the NAME, not just the ORDER BY. Every verdict row used to be
-- called 'first cause', so `ORDER BY ord, name` tied between them and could not
-- put them in priority order — while the comment above claimed the first was the
-- one to fix. Numbering them makes the claim true and the priority visible.
SELECT 6, 'verdict', format('cause %s', rank), cause
  FROM (
    SELECT 1 AS rank,
           'The alerts table is EMPTY. Seed it, or check NEXT_PUBLIC_SUPABASE_URL '
           || 'points at this project.' AS cause
      FROM headline WHERE alerts_total = 0
    UNION ALL
    SELECT 2,
           'No account has a staff role, so row-level security gives every account '
           || 'only its own reports. Set one profile to HQ_COMMAND.'
      FROM headline WHERE staff_profiles = 0
    UNION ALL
    SELECT 3,
           'Staff exist but NONE can see the whole state, and no staff account can '
           || 'see any incident. Row-level security is refusing every read — the '
           || 'console shows FEED UNAVAILABLE, not ALL SECTORS CLEAR.'
      FROM headline h
     WHERE h.staff_profiles > 0
       AND NOT EXISTS (SELECT 1 FROM visibility v
                        WHERE upper(coalesce(v.role, '')) <> 'CITIZEN'
                          AND v.would_see > 0)
       AND (SELECT total FROM incidents) > 0
    UNION ALL
    SELECT 4,
           'At least one staff account can see incidents, so the read is not the '
           || 'problem for that account. If the board still looks empty, a FILTER '
           || 'is hiding them — the board says NO MATCH FOR THESE FILTERS and names '
           || 'how many are withheld. Check the geography rows above against the '
           || 'tactical map, and the `would see` row for YOUR account.'
      FROM headline h
     WHERE h.staff_profiles > 0
       AND (SELECT total FROM incidents) > 0
       AND EXISTS (SELECT 1 FROM visibility v
                    WHERE upper(coalesce(v.role, '')) <> 'CITIZEN'
                      AND v.would_see > 0)
    UNION ALL
    SELECT 5,
           'Incidents are unacknowledged with an empty outbox: the escalation job is '
           || 'not running (rainbow-escalate-overdue).'
      FROM pipeline p WHERE p.unacknowledged > 0 AND p.outbox_rows = 0
    UNION ALL
    SELECT 6,
           'The outbox has undelivered rows that have been attempted: the drain '
           || 'worker is not running, or is failing. See the newest outbox error.'
      FROM pipeline p WHERE p.outbox_erroring > 0
  ) AS verdicts
 ORDER BY ord, name;
