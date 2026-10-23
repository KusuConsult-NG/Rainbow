-- A ward escalation was addressed to nobody, and so was an LGA one.
--
-- ## What the deployment carries
--
-- The production project's 22 staff accounts are spelled `STATE_COMMANDER`
-- (×4), `LGA_COMMANDER` (×4), `WARD_COMMANDER` (×4) and
-- `POLLING_UNIT_OFFICER` (×6). This repository was written against
-- `HQ_COMMAND` / `LGA_COMMAND` / `WARD_COMMAND` / `UNIT_COMMAND`.
--
-- `20261028000000_command_knows_both_vocabularies` taught `is_command()` and
-- `commands_whole_state()` both spellings. It did not touch
-- `escalation_push_targets()`, which carries FOUR MORE exact-match lists of
-- its own — and that function decides whose phone an automatic escalation
-- reaches:
--
--     WHEN 'UNIT' THEN ARRAY['UNIT_COMMAND','POLLING_UNIT_OFFICER','POLLING_OFFICER']
--     WHEN 'WARD' THEN ARRAY['WARD_COMMAND','WARD_OFFICER']
--     WHEN 'LGA'  THEN ARRAY['LGA_COMMAND','LGA_OFFICER']
--     WHEN 'HQ'   THEN ARRAY['HQ_COMMAND','HQ_OFFICER','ADMIN']
--
-- Against that deployment:
--
--     WARD -> 0 recipients   (WARD_COMMANDER is not WARD_COMMAND)
--     LGA  -> 0 recipients   (LGA_COMMANDER is not LGA_COMMAND)
--     HQ   -> 1 recipient    (the single HQ_COMMAND account)
--     UNIT -> 6 recipients   — works, and only because somebody hit this for
--                              that one rung and added POLLING_UNIT_OFFICER to
--                              that one list
--
-- `deliverTierEscalation` throws "no reachable officer at that tier" on an
-- empty list — deliberately, so the notice is retried rather than recorded as
-- delivered. So every ward and LGA escalation on that project was a
-- notification that could never be delivered to anybody, for ever. The
-- automatic escalation moved the incident and told nobody, which is the exact
-- failure `20261007000000_notification_outbox` was written to end.
--
-- ## One list, derived
--
-- Adding three names to four arrays fixes today and leaves the shape that
-- produced this. `roles_for_tier()` is the only place in SQL a staff role name
-- is written against a rung, and `escalation_push_targets()` asks it. The
-- console's `src/lib/command-roles.ts` and the app's `staffRoleTiers` are the
-- same decision in the other two languages, and
-- `scripts/check_one_command_vocabulary.py` asserts all three agree — it used
-- to read two of them, which is why this survived T-85 and T-90.
--
-- See E2E_AUDIT_REPORT.md T-97.

CREATE OR REPLACE FUNCTION public.roles_for_tier(p_tier TEXT)
RETURNS TEXT[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT CASE upper(coalesce(btrim(p_tier), ''))
    -- Both spellings of the rung, and both desk names. An escalation is
    -- addressed to a desk rather than to a person: at two in the morning the
    -- commander is not necessarily the one awake.
    WHEN 'UNIT' THEN ARRAY[
      'UNIT_COMMAND', 'POLLING_UNIT_OFFICER', 'POLLING_OFFICER']
    WHEN 'WARD' THEN ARRAY[
      'WARD_COMMAND', 'WARD_COMMANDER', 'WARD_OFFICER']
    WHEN 'LGA' THEN ARRAY[
      'LGA_COMMAND', 'LGA_COMMANDER', 'LGA_OFFICER']
    WHEN 'HQ' THEN ARRAY[
      'HQ_COMMAND', 'STATE_COMMANDER', 'HQ_OFFICER', 'ADMIN']
    -- A tier nobody holds addresses nobody. Failing open here would page the
    -- whole state on a malformed payload.
    ELSE ARRAY[]::TEXT[]
  END;
$$;

COMMENT ON FUNCTION public.roles_for_tier(TEXT) IS
  'Every staff role that holds a rung, in both the vocabulary this repository '
  'is written against and the one the deployment actually carries. The single '
  'SQL definition: escalation_push_targets() asks it rather than carrying its '
  'own lists, which is how a ward escalation came to be addressed to nobody.';

REVOKE ALL ON FUNCTION public.roles_for_tier(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.roles_for_tier(TEXT)
  TO anon, authenticated, service_role;

-- ── And the one caller asks it ──────────────────────────────────────────────
--
-- Same body as 20261009000000 otherwise: the geography branch is unchanged, HQ
-- is still statewide and unfiltered, and an incident with no location still
-- reaches the tier regardless of posting.

CREATE OR REPLACE FUNCTION public.escalation_push_targets(p_outbox_id BIGINT)
RETURNS TABLE (user_id UUID, player_id TEXT, role TEXT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  WITH notice AS (
    SELECT o.payload
      FROM public.notification_outbox o
     WHERE o.id = p_outbox_id
       AND o.kind = 'TIER_ESCALATION'
  ),
  want AS (
    SELECT upper(coalesce(payload ->> 'to_tier', ''))  AS tier,
           public.geo_key(payload ->> 'geo_lga')       AS lga,
           public.geo_key(payload ->> 'geo_ward')      AS ward,
           public.geo_key(payload ->> 'geo_pu')        AS pu
      FROM notice
  )
  SELECT p.id, p.onesignal_player_id, p.role
    FROM public.profiles p, want w
   WHERE p.onesignal_player_id IS NOT NULL
     AND length(p.onesignal_player_id) > 5
     AND upper(coalesce(p.role, '')) = ANY (public.roles_for_tier(w.tier))
     AND (
       w.tier = 'HQ'
       OR w.lga IS NULL
       OR (
         public.geo_key(p.geo_lga) = w.lga
         AND (w.tier <> 'WARD' OR w.ward IS NULL
              OR public.geo_key(p.geo_ward) = w.ward)
         AND (w.tier <> 'UNIT' OR w.pu IS NULL
              OR public.geo_key(p.geo_pu) = w.pu)
       )
     );
$$;

COMMENT ON FUNCTION public.escalation_push_targets(BIGINT) IS
  'Whose phone an automatic escalation is for. Roles come from '
  'roles_for_tier(); geography is compared through geo_key(), and HQ is '
  'statewide and unfiltered because its job is everything.';

REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalation_push_targets(BIGINT)
  FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.escalation_push_targets(BIGINT) TO service_role;

-- ── What this just changed, in accounts ─────────────────────────────────────
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT t.tier,
           count(*) FILTER (
             WHERE upper(coalesce(p.role, '')) = ANY (public.roles_for_tier(t.tier))
           ) AS reachable
      FROM (VALUES ('HQ'), ('LGA'), ('WARD'), ('UNIT')) AS t(tier)
      LEFT JOIN public.profiles p ON true
     GROUP BY t.tier
     ORDER BY t.tier
  LOOP
    RAISE NOTICE 'tier % is now held by % account(s) on this database',
      r.tier, r.reachable;
  END LOOP;
  RAISE NOTICE
    'A tier reading 0 has nobody to escalate to: that is a staffing or a '
    'profiles.role spelling problem, not a code one. Run '
    'scripts/why_is_the_board_empty.sql for the role table.';
END $$;
