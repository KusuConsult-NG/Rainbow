--
-- ONE PART OF scripts/apply_all_migrations.sql — generated, do not edit by hand.
--   Regenerate with: python3 scripts/build_apply_in_parts.py
--
-- Run the parts IN NUMBER ORDER, each on its own, letting each finish before the
-- next. The order is not cosmetic: part 02 drops the permissive policy set BY
-- NAME, and several later parts assume columns an earlier part adds.
--
-- Expect `NOTICE: skipping ...` lines — they are the guards that let these files
-- run against a database that does not have a given table yet.
--
-- ONE PART BEHAVES DIFFERENTLY IF YOU RUN IT TWICE. Part 02, the RLS policy
-- migration, is ATOMIC rather than idempotent: it drops the old policy set by
-- name and creates a new one inside its own BEGIN/COMMIT. Run it a second time
-- and it says
--
--     ERROR: policy "profiles_select_self_or_staff" for table "profiles"
--            already exists
--
-- and rolls itself back. That message means THE POLICIES ARE ALREADY IN PLACE.
-- Nothing is half-applied, and part 15 will still report every row PASS.
--
-- Part 15 is the readout: it writes nothing and tells you the truth about the
-- whole set. It needs parts 01-14 applied first, because it checks work they do;
-- run it early and it says so plainly rather than failing on a missing function.
--
-- The LAST part writes nothing. It returns one row per thing that had to be
-- true, and every one of them must read PASS.
--
-- If you can paste the whole of apply_all_migrations.sql in one go, do that
-- instead: one paste cannot be run out of order or stopped halfway by accident.
--

-- ----------------------------------------------------------------------------
-- 20261028000000_command_knows_both_vocabularies.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261028000000_command_knows_both_vocabularies.sql'; END $apply$;

-- ============================================================================
-- The command tier the deployment actually has
--
-- T-85 found that `auth_provider.dart` chose an officer's rung by substring
-- test, so `STATE_COMMANDER` — the role 4 of the production project's HQ duty
-- officers carry — matched none of HQ/LGA/WARD/UNIT/POLLING and was silently
-- treated as a polling unit. That is fixed in the app.
--
-- The database has the same problem, one layer down, where the app's fix cannot
-- reach. Two functions decide what a commander may DO, and both are exact-match
-- lists of the vocabulary this repository was written against:
--
--     is_command()          IN ('HQ_COMMAND','HQ_OFFICER','ADMIN','LGA_COMMAND')
--     commands_whole_state() IN ('HQ_COMMAND','HQ_OFFICER','ADMIN')
--
-- The production project's 22 staff accounts carry `STATE_COMMANDER` (×4),
-- `LGA_COMMANDER` (×4), `WARD_COMMANDER` (×4) and `POLLING_UNIT_OFFICER` (×6).
-- Exactly TWO accounts — one HQ_COMMAND and one LGA_COMMAND — satisfy
-- `is_command()`. Every other commander is refused by every policy gated on it:
--
--   * system_alerts     write / update / delete   — THE ADVISORY BROADCAST
--   * safe_zones        write                     — publishing a shelter
--   * agency_personnel / agency_deployments /
--     agency_action_reports / agency_notifications — the whole agency portal
--   * sim_channel_events acknowledge              — a SIM swap on a handset
--   * uninstall_requests update                   — approving an uninstall
--
-- And `commands_whole_state()` is why the empty-board diagnostic reports
-- `steviekusu@gmail.com` (HQ_COMMAND) seeing "156 of 156, commands the whole
-- state" while hq-001 and hq-002 (STATE_COMMANDER) see 106: their scope falls
-- back to their posting, which is one polling unit in Bukuru.
--
-- `is_staff()` is NOT affected, because it is written as an exclusion —
-- `NOT IN ('CITIZEN','USER')` — so every staff name passes it whatever it is
-- called. That is why those accounts could READ incidents all along, and why
-- the failure looked like a filter rather than a permission.
--
-- ## Why widening these is safe
--
-- `profiles.role` cannot be chosen or changed by any authenticated user: the
-- trigger in 20260813000000 section 4 raises 42501 on ANY role change unless
-- the caller is service_role. So recognising a name grants nothing a user can
-- give themselves — the backend assigns roles, and a citizen cannot become a
-- STATE_COMMANDER to obtain these rights.
--
-- ## What is deliberately NOT added
--
-- `WARD_COMMANDER` and `POLLING_UNIT_OFFICER`. `is_command()` already excludes
-- `WARD_COMMAND` and `UNIT_COMMAND`, so their synonyms stay out too — this
-- migration teaches the database a second spelling, it does not move anybody up
-- the chain.
--
-- Idempotent: both are CREATE OR REPLACE over a pure SELECT.
-- See E2E_AUDIT_REPORT.md T-85 and T-90.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_command()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT upper(coalesce(role, '')) FROM public.profiles WHERE id = auth.uid())
      IN (
        -- The vocabulary this repository is written against.
        'HQ_COMMAND', 'HQ_OFFICER', 'ADMIN', 'LGA_COMMAND',
        -- The vocabulary the production project's accounts carry. Same two
        -- rungs, different spelling. T-90.
        'STATE_COMMANDER', 'LGA_COMMANDER'
      ),
    false
  );
$$;

COMMENT ON FUNCTION public.is_command() IS
  'HQ, administrators and LGA command, under either vocabulary. Was an '
  'exact-match list of HQ_COMMAND/HQ_OFFICER/ADMIN/LGA_COMMAND, which left '
  'the production project''s STATE_COMMANDER and LGA_COMMANDER accounts — 8 of '
  'its 22 staff — unable to post an advisory, publish a shelter, use the '
  'agency portal or acknowledge a SIM swap. upper() so case cannot decide a '
  'permission either. See T-90.';

CREATE OR REPLACE FUNCTION public.commands_whole_state()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT upper(coalesce(role, '')) FROM public.profiles WHERE id = auth.uid())
      IN (
        'HQ_COMMAND', 'HQ_OFFICER', 'ADMIN',
        -- The HQ rung's other spelling. Without this an HQ duty officer's
        -- incident scope silently fell back to their posting — one polling
        -- unit — which is what the empty-board diagnostic was reporting. T-90.
        'STATE_COMMANDER'
      ),
    false
  );
$$;

COMMENT ON FUNCTION public.commands_whole_state() IS
  'HQ and administrators, under either vocabulary. Narrower than is_command(), '
  'which also includes the LGA rung. STATE_COMMANDER added by T-90: without it '
  'an HQ duty officer saw only their posting.';

-- Say what changed, loudly, because this one alters who may do what.
DO $say$
DECLARE
  n_command INTEGER;
  n_state   INTEGER;
BEGIN
  SELECT count(*) INTO n_command
    FROM public.profiles
   WHERE upper(coalesce(role, '')) IN
         ('HQ_COMMAND','HQ_OFFICER','ADMIN','LGA_COMMAND',
          'STATE_COMMANDER','LGA_COMMANDER');
  SELECT count(*) INTO n_state
    FROM public.profiles
   WHERE upper(coalesce(role, '')) IN
         ('HQ_COMMAND','HQ_OFFICER','ADMIN','STATE_COMMANDER');
  RAISE NOTICE
    'is_command() now matches % profile(s); commands_whole_state() matches %. '
    'If either number surprises you, read profiles.role before going further.',
    n_command, n_state;
END $say$;



