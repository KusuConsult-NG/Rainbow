-- One officer, two accounts, and the posting is on the other one.
--
-- ## What the deployment has
--
-- Duplicate staff accounts across two email domains. Staff do not sign in with
-- an email — they type a badge, and the app turns it into one:
--
--     '$trimmed@operationrainbow.plateau.gov.ng'
--
-- with the console carrying its own copy of that domain. The domain is the
-- second half of the primary key of a person: provision an account under a
-- different one, or change it, and the SAME badge resolves to a DIFFERENT
-- `auth.users` row.
--
-- It is not a cosmetic duplicate:
--
--   * the posting (`geo_lga`, `geo_ward`) is set on one of the two accounts.
--     The officer signs in and lands on the other, where it is blank, so
--     `alert_in_my_area()` matches nothing and their board is empty with the
--     incidents right there. Same symptom as T-95's ward suffix and T-90's role
--     spelling, from a third cause — which is why "nothing was seen on the HQ
--     dashboard" has been three different bugs.
--   * `onesignal_player_id` is on one of them, so `escalation_push_targets()`
--     either misses that officer or, when both carry a posting, tells them
--     twice.
--   * `alerts.assigned_to_uid` points at whichever account was open when the
--     dispatch was made, so an incident can be assigned to the account its
--     owner is not signed into.
--
-- `profiles.badge_number` would have caught it, and does not. 20260903000004
-- gives it a plain index and no uniqueness, so two accounts may hold one badge
-- — and the badge is what officers are called on the radio, what every board
-- labels them with, and what `formatOfficerBadge()` falls back to SCANNING
-- every profile for, taking whichever row comes first.
--
-- ## What a migration can and cannot do here
--
-- It cannot decide which of two accounts is the real one. That is a person's
-- call: one of them has the posting, one has the password the officer actually
-- knows, and only they know which.
--
-- So this adds the three things that let somebody make that call safely — a
-- view that names the duplicates and what each side holds, a function that
-- merges one into another without deleting anything, and the uniqueness
-- constraint, attempted and reported rather than forced.

-- ── Which accounts are the same person ──────────────────────────────────────
--
-- Two keys, because the deployment has both shapes:
--
--   badge   two accounts carrying the same badge_number. The strongest signal:
--           a badge IS the officer.
--   local   the same email local-part on different domains — hq-001@a.ng and
--           hq-001@b.ng — which is precisely what "duplicates across two email
--           domains" means, and what the badge-to-email derivation produces
--           when the domain changes.
--
-- `phone` is not a key here: profiles.phone is already UNIQUE, so it cannot
-- duplicate. Which is also why this was invisible — the one identity column
-- with a constraint on it is the one that was never the problem.

CREATE OR REPLACE VIEW public.staff_account_duplicates AS
WITH staff AS (
  SELECT p.id, p.email, p.badge_number, p.role, p.full_name,
         p.geo_lga, p.geo_ward, p.geo_pu, p.onesignal_player_id,
         p.is_active, p.created_at, p.last_seen,
         nullif(upper(btrim(coalesce(p.badge_number, ''))), '')  AS badge_key,
         nullif(lower(split_part(coalesce(p.email, ''), '@', 1)), '') AS local_key,
         lower(split_part(coalesce(p.email, ''), '@', 2))        AS domain
    FROM public.profiles p
   WHERE upper(coalesce(p.role, '')) NOT IN ('CITIZEN', 'USER')
),
-- Aggregated per key in a CTE rather than with a window function:
-- `count(DISTINCT x) OVER (...)` is not implemented in PostgreSQL, and the
-- first version of this view used it and would not parse.
by_badge AS (
  SELECT badge_key, count(*) AS accounts
    FROM staff WHERE badge_key IS NOT NULL GROUP BY badge_key
),
by_local AS (
  SELECT local_key, count(*) AS accounts, count(DISTINCT domain) AS domains
    FROM staff WHERE local_key IS NOT NULL GROUP BY local_key
)
SELECT
  coalesce(
    CASE WHEN b.accounts > 1 THEN s.badge_key END,
    s.local_key)                                         AS officer_key,
  CASE WHEN b.accounts > 1 THEN 'same badge'
       ELSE 'same name, two domains' END                 AS matched_on,
  s.id, s.email, s.domain, s.badge_number, s.role, s.full_name,
  s.geo_lga, s.geo_ward, s.geo_pu,
  (s.onesignal_player_id IS NOT NULL
     AND length(s.onesignal_player_id) > 5)              AS can_be_pushed,
  s.is_active, s.created_at, s.last_seen,
  -- What this account would lose if it were the one retired. The whole point
  -- of the view: an operator picking which to keep needs to see it.
  (SELECT count(*) FROM public.alerts a
    WHERE a.assigned_to_uid = s.id)                      AS alerts_assigned,
  (SELECT count(*) FROM public.alerts a
    WHERE a.reported_by = s.id)                          AS alerts_reported
  FROM staff s
  LEFT JOIN by_badge b ON b.badge_key = s.badge_key
  LEFT JOIN by_local l ON l.local_key = s.local_key
 WHERE coalesce(b.accounts, 0) > 1
    OR (coalesce(l.accounts, 0) > 1 AND coalesce(l.domains, 0) > 1);

COMMENT ON VIEW public.staff_account_duplicates IS
  'Staff accounts that look like the same officer twice: one badge on two '
  'accounts, or one email local-part on two domains. Shows which side holds '
  'the posting, the push id and the incidents, because that is what decides '
  'which one to keep. Read it before calling merge_staff_account().';

-- A view inherits the RLS of the tables under it, and `profiles` is already
-- scoped. Granted to the roles that can read profiles at all; the citizen app
-- has no reason to select it, so authenticated gets it only because the console
-- runs as a signed-in operator.
REVOKE ALL ON public.staff_account_duplicates FROM PUBLIC, anon;
GRANT SELECT ON public.staff_account_duplicates TO authenticated, service_role;

-- ── Merging one into another, without deleting anything ────────────────────

CREATE OR REPLACE FUNCTION public.merge_staff_account(
  p_keep   UUID,
  p_retire UUID)
RETURNS TABLE (moved TEXT, detail TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  k public.profiles;
  r public.profiles;
  n INTEGER;
BEGIN
  IF NOT public.is_command() THEN
    RAISE EXCEPTION 'only command may merge staff accounts'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF p_keep IS NULL OR p_retire IS NULL OR p_keep = p_retire THEN
    RAISE EXCEPTION 'merge needs two different accounts';
  END IF;

  SELECT * INTO k FROM public.profiles WHERE id = p_keep;
  SELECT * INTO r FROM public.profiles WHERE id = p_retire;
  IF k.id IS NULL THEN RAISE EXCEPTION 'no profile %', p_keep; END IF;
  IF r.id IS NULL THEN RAISE EXCEPTION 'no profile %', p_retire; END IF;
  IF upper(coalesce(k.role, '')) IN ('CITIZEN', 'USER')
     OR upper(coalesce(r.role, '')) IN ('CITIZEN', 'USER') THEN
    -- A citizen's account is their own and is not a duplicate desk. Merging
    -- one would move another person's reports onto somebody else's id.
    RAISE EXCEPTION
      'merge_staff_account is for STAFF accounts. % / % includes a citizen',
      k.role, r.role;
  END IF;

  -- Incidents first, because they are the thing that must not be orphaned.
  UPDATE public.alerts SET assigned_to_uid = p_keep
   WHERE assigned_to_uid = p_retire;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN QUERY SELECT 'alerts reassigned', format('%s incident(s)', n);

  -- THE RETIRED ACCOUNT IS STOOD DOWN BEFORE THE KEPT ONE IS FILLED IN.
  --
  -- The order is not cosmetic. `profiles_badge_number_unique` covers ACTIVE
  -- rows, so setting WD-900 on the kept account while the retired one still
  -- holds it and is still active raises `23505` and the whole merge rolls back.
  -- The first version of this function did exactly that, and the replay probe
  -- is what found it — the constraint added in this same migration refusing
  -- the function added in this same migration.
  --
  -- Deactivated, never deleted: a delete cascades to `auth.users` and takes
  -- the record of who reported what with it. It also loses the things that
  -- made the row look live — the badge (so it stops matching a radio call),
  -- the posting (so it matches no incident) and the push id (so it is never
  -- told anything).
  UPDATE public.profiles
     SET is_active = false,
         badge_number = NULL,
         geo_lga = NULL, geo_ward = NULL, geo_pu = NULL,
         onesignal_player_id = NULL,
         full_name = coalesce(nullif(btrim(coalesce(r.full_name, '')), ''), '')
                     || ' [MERGED INTO ' || p_keep::text || ']',
         updated_at = NOW()
   WHERE id = p_retire;
  RETURN QUERY SELECT 'retired account stood down',
    format('%s is inactive, unbadged and unreachable; its reports stay on it',
           coalesce(r.email, p_retire::text));

  -- The posting, the badge and the push id move only when the kept account
  -- does NOT already have one. A merge must never overwrite what the surviving
  -- account knows about itself with what the abandoned one guessed: the
  -- survivor is the row somebody actually signs into.
  --
  -- Read from `r`, the snapshot taken before either UPDATE, so clearing the
  -- retired row above does not erase what we are moving across.
  UPDATE public.profiles
     SET geo_lga   = coalesce(nullif(btrim(coalesce(k.geo_lga, '')), ''), r.geo_lga),
         geo_ward  = coalesce(nullif(btrim(coalesce(k.geo_ward, '')), ''), r.geo_ward),
         geo_pu    = coalesce(nullif(btrim(coalesce(k.geo_pu, '')), ''), r.geo_pu),
         badge_number = coalesce(nullif(btrim(coalesce(k.badge_number, '')), ''),
                                 r.badge_number),
         full_name = coalesce(nullif(btrim(coalesce(k.full_name, '')), ''),
                              r.full_name),
         onesignal_player_id = coalesce(
           nullif(k.onesignal_player_id, ''), r.onesignal_player_id),
         updated_at = NOW()
   WHERE id = p_keep;
  RETURN QUERY SELECT 'kept account filled in',
    format('posting %s / %s, badge %s',
           coalesce(nullif(btrim(coalesce(k.geo_lga, '')), ''), r.geo_lga, '—'),
           coalesce(nullif(btrim(coalesce(k.geo_ward, '')), ''), r.geo_ward, '—'),
           coalesce(nullif(btrim(coalesce(k.badge_number, '')), ''),
                    r.badge_number, '—'));
END;
$$;

COMMENT ON FUNCTION public.merge_staff_account(UUID, UUID) IS
  'Moves one duplicate staff account into another: reassigns incidents, fills '
  'any blank on the kept account from the retired one, and stands the retired '
  'one down without deleting it. Command only. Read '
  'staff_account_duplicates first — this cannot decide which account is the '
  'real one.';

REVOKE ALL ON FUNCTION public.merge_staff_account(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.merge_staff_account(UUID, UUID)
  TO authenticated, service_role;

-- ── And a badge becomes an identity, if this database lets it ──────────────
--
-- Attempted, not forced. On a database that already has two accounts per
-- officer the index cannot be built, and failing the migration there would
-- block every later one — on exactly the database that needs them. So it is
-- tried, and when it cannot be had the operator is told what to do about it.

DO $$
BEGIN
  CREATE UNIQUE INDEX profiles_badge_number_unique
    ON public.profiles (upper(btrim(badge_number)))
   WHERE badge_number IS NOT NULL
     AND btrim(badge_number) <> ''
     AND is_active;
  RAISE NOTICE
    'profiles_badge_number_unique created: one active account per badge from now on';
EXCEPTION
  WHEN duplicate_table THEN
    RAISE NOTICE 'profiles_badge_number_unique already exists';
  WHEN unique_violation THEN
    RAISE WARNING
      'Could not make badge_number unique: this database has more than one '
      'ACTIVE account carrying the same badge. That is the duplicate-account '
      'problem itself. Run: select * from public.staff_account_duplicates '
      'order by officer_key; decide which account is the real one, then '
      'select * from public.merge_staff_account(''<keep>'', ''<retire>''); and '
      're-run this migration to take the constraint.';
END $$;

-- Scoped to ACTIVE accounts on purpose: a merged account keeps its history and
-- is_active = false, and the constraint must not be the reason a merge is
-- impossible. It also means re-running this file after the merges succeeds.
