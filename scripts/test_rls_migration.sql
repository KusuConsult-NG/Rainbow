-- ============================================================================
-- Harness: prove 20260813000000_rls_least_privilege.sql actually does what it
-- claims, against a real PostgreSQL — before it is run on a live database.
--
-- Supabase provides `auth.uid()`, `auth.role()` and the anon/authenticated
-- roles. Vanilla Postgres does not, so they are stubbed here with the same
-- semantics: auth.uid() reads a session GUC, which is how Supabase's PostgREST
-- layer conveys the caller's identity.
--
-- Run: see scripts/verify_rls_migration.sh
-- ============================================================================

-- ── Supabase compatibility shims ────────────────────────────────────────────
CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE IF NOT EXISTS auth.users (
  id UUID PRIMARY KEY,
  email TEXT,
  phone TEXT,
  raw_user_meta_data JSONB DEFAULT '{}'::jsonb
);

CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), 'anon');
$$;

DO $$ BEGIN
  CREATE ROLE anon NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE authenticated NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE ROLE service_role NOLOGIN BYPASSRLS;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA auth TO anon, authenticated, service_role;
