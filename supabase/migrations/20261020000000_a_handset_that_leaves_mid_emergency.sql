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
