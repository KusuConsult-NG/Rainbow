-- ============================================================================
-- OPERATION RAINBOW — A SIGNUP MAY NOT CHOOSE ITS OWN ROLE
--
-- THE HOLE
--
-- `handle_new_user()` has, since the initial schema, created the profile like
-- this:
--
--     role := COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')
--
-- `raw_user_meta_data` is `options.data` from `supabase.auth.signUp`, written
-- by whoever is signing up, with the anon key — which ships inside the APK and
-- inside the browser bundle, by design, because row-level security is meant to
-- be the whole access model.
--
-- So this was enough to become a commander:
--
--     supabase.auth.signUp({
--       email, password,
--       options: { data: { role: 'HQ_COMMAND' } },
--     })
--
-- and `is_command()` / `is_staff()` read `profiles.role`, so that account then
-- passes every policy in the RLS migration: the full incident board, live
-- telemetry for every citizen who has pressed SOS, dispatch, escalation, mass
-- broadcast to the whole state.
--
-- WHY THE EXISTING GUARD DID NOT COVER IT
--
-- `profiles_no_privilege_escalation` is BEFORE UPDATE. The escalation is not an
-- update — the role is chosen at INSERT, by the signup itself. README.md said
-- "nothing reads user_metadata", which was true of the policies and not true of
-- the trigger that creates the row the policies read.
--
-- THE FIX
--
-- Signup no longer reads `role` at all. Every account created through the
-- public auth endpoint is a CITIZEN, whatever it asks for, and `full_name` and
-- `phone` are still honoured because they are not privileges.
--
-- Staff are provisioned by a privileged caller instead: create the account,
-- then set `profiles.role` with the service key. That path is unaffected — the
-- UPDATE guard already exempts `service_role` — and it is what
-- `/api/admin/provision` now does. The console's "Provision Security Personnel
-- Account" form used to rely on the hole: it passed the chosen role in
-- `options.data` and the trigger obligingly applied it.
--
-- A NOTE ON WHAT IS NOT DONE HERE
--
-- Existing profiles are left alone. This migration cannot tell an account that
-- was legitimately provisioned as HQ_COMMAND from one that asked to be. That
-- audit is in E2E_AUDIT_REPORT.md as an operational step, with the query for
-- it, because it needs a human who knows who is supposed to be staff.
--
-- Idempotent: safe to re-run.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
-- SECURITY DEFINER with no search_path is how a SECURITY DEFINER function gets
-- hijacked by a schema earlier on the caller's path. Pinned.
SET search_path = public, pg_temp
AS $func$
BEGIN
  INSERT INTO public.profiles (id, email, phone, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'User'),
    -- NOT from the metadata. A signup does not get to say what it is.
    'CITIZEN'
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    updated_at = NOW();
  RETURN NEW;
END;
$func$;

-- The trigger itself is unchanged in shape; recreated so this file is complete
-- on a database that somehow lacks it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
