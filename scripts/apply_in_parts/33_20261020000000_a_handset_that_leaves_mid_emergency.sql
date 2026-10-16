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
-- 20261020000000_a_handset_that_leaves_mid_emergency.sql
-- ----------------------------------------------------------------------------
DO $apply$ BEGIN RAISE NOTICE 'applying 20261020000000_a_handset_that_leaves_mid_emergency.sql'; END $apply$;

-- ============================================================================
-- A HANDSET THAT SIGNS OUT WHILE ITS EMERGENCY IS STILL OPEN
-- ============================================================================
--
-- `AuthService.signOut()` stopped location tracking first, deliberately, and
-- said why:
--
--     Signing out is the clearest statement a person can make that they are
--     done being observed, and it was the one action that did not stop it.
--
-- That is right about a person signing out of their own phone. It is wrong
-- about the one case the duress design exists for. A duress PIN tells the
-- person their alarm is cancelled and KEEPS TRACKING RUNNING, because they may
-- still be in danger — and the lock screen offers a sign-out that needs no code
-- at all. So whoever is holding the phone could end the tracking of a live
-- duress alert without knowing any PIN, and HQ saw silence indistinguishable
-- from a flat battery.
--
-- Two rules collided and nothing recorded which won. Now: signing out ends the
-- session and retires the SMS key as before, a RESPONDER's patrol track still
-- stops (they are off duty), and an SOS track keeps running until the incident
-- closes or the twelve-hour ceiling in `sosTrackingMaxAge` expires.
--
-- This column is the other half: the loss of the app has to be visible as a
-- FACT rather than inferred from a gap. An operator watching a track go quiet
-- cannot tell a captor from a dead phone; one that says "this handset signed
-- out at 19:42, tracking continues" can.
--
-- Written by the handset itself, in the window before the session is cleared,
-- so `alerts_update_own_or_ours` covers it: `reported_by = auth.uid()`.
-- Best-effort by design — a phone being switched off must not have the sign-out
-- blocked on a network write.
-- ============================================================================

BEGIN;

ALTER TABLE public.alerts
  ADD COLUMN IF NOT EXISTS device_signed_out_at TIMESTAMPTZ;

COMMENT ON COLUMN public.alerts.device_signed_out_at IS
  'When the reporting handset signed out while this incident was still open. '
  'Tracking continues regardless; this says the app is gone, so an operator can '
  'tell that from a dead battery. Written by the handset before its session '
  'ends, best-effort.';

-- The console reads it on one incident at a time, from the dossier, so no index
-- is warranted. Said out loud because the next column added here will be
-- tempted to copy an index it does not need either.

COMMIT;

