-- ─── Supabase stand-ins for a plain PostgreSQL instance ──────────────────────
--
-- The migrations in supabase/migrations reference objects that Supabase creates
-- and manages for you: the `auth` schema, `auth.uid()` / `auth.role()`, the
-- anon / authenticated / service_role roles, and the `supabase_realtime`
-- publication. On a bare Postgres — CI, or a local scratch database — none of
-- those exist, so the migrations cannot run.
--
-- This file creates just enough of them to apply the migrations and exercise
-- the SQL logic. It is a TEST FIXTURE:
--
--   * NEVER apply it to a real Supabase project. Supabase owns these objects;
--     redefining them there would be actively harmful.
--   * It does not reproduce Supabase's auth behaviour. auth.uid() here simply
--     reads a session GUC, which is what lets a test impersonate a user with
--     `SET request.jwt.claim.sub = '<uuid>'`.
--
-- Idempotent; safe to re-run.

DO $shim$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN;
  END IF;
END $shim$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO anon, authenticated, service_role;

CREATE SCHEMA IF NOT EXISTS auth;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS auth.users (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email              TEXT,
  phone              TEXT,
  raw_user_meta_data JSONB DEFAULT '{}'::JSONB
);

-- Supabase derives these from the request's JWT. Here they read the session
-- GUCs, so a test can impersonate a caller:
--     SET ROLE authenticated;
--     SET request.jwt.claim.sub = '<uuid>';
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;

GRANT EXECUTE ON FUNCTION auth.uid(), auth.role() TO anon, authenticated, service_role;

DO $shim$
BEGIN
  CREATE PUBLICATION supabase_realtime;
EXCEPTION WHEN duplicate_object THEN NULL;
END $shim$;
