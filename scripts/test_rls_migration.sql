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

-- ── Supabase Storage shim ───────────────────────────────────────────────────
-- Enough of storage.buckets / storage.objects for
-- 20260903000001_incident_media_storage.sql to run and for its policies to be
-- exercised. Shapes follow the real schema; the API roles hold table grants
-- there too (RLS, not grants, is what gates access), and objects has RLS on
-- with no policies until a migration adds some.
CREATE SCHEMA IF NOT EXISTS storage;

CREATE TABLE IF NOT EXISTS storage.buckets (
  id                 TEXT PRIMARY KEY,
  name               TEXT NOT NULL,
  owner              UUID,
  public             BOOLEAN DEFAULT false,
  file_size_limit    BIGINT,
  allowed_mime_types TEXT[],
  created_at         TIMESTAMPTZ DEFAULT NOW(),
  updated_at         TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id  TEXT REFERENCES storage.buckets(id),
  name       TEXT,
  owner      UUID,
  owner_id   TEXT,
  metadata   JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;
GRANT ALL ON storage.buckets, storage.objects TO anon, authenticated, service_role;
