-- ════════════════════════════════════════════════════════════════════════════════
-- OPERATION RAINBOW — RLS GEO_LGA SCOPING (STAGING MIGRATION)
-- File: supabase/migrations/20260725000000_v6_geo_lga_scoping_staging.sql
--
-- ⚠️  STAGING FIRST. Do NOT apply to production until:
--   1. All existing officer profiles have geo_lga populated and normalised
--   2. verify_rls.js passes on staging
--   3. At least one officer in each LGA has confirmed they can see their alerts
--
-- What this does:
--   • Officers (FIELD_OFFICER, WARD_OFFICER, LGA_OFFICER) see alerts scoped to
--     their geo_lga. Officers with a NULL or '' geo_lga fall through to the
--     existing "all responders" policy — they lose nothing, they just don't get
--     the narrowed view until their profile is updated.
--   • HQ_COMMAND / HQ_OFFICER / ADMIN still see everything (unchanged).
--   • Citizens still see only their own alerts (unchanged).
--
-- Safe rollback: DROP POLICY "alerts_select_geo_lga_scoped" ON public.alerts;
-- ════════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Helper: normalise LGA strings before comparing ───────────────────────────
-- Strips leading/trailing whitespace and lowercases both sides so that
-- "Jos North" and "jos north " compare equal.

CREATE OR REPLACE FUNCTION public.normalise_lga(lga TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT LOWER(TRIM(lga));
$$;

-- ── Scoped officer policy ─────────────────────────────────────────────────────
-- Only applies when:
--   a) The caller is a field/ward/LGA officer (not HQ, not citizen)
--   b) The officer's profile has a non-empty geo_lga
-- When either condition is false the policy produces no rows (it doesn't fire),
-- so the existing "alerts_select_responders" policy still covers HQ and officers
-- whose geo_lga is not yet filled in.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'alerts'
      AND policyname = 'alerts_select_geo_lga_scoped'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "alerts_select_geo_lga_scoped"
        ON public.alerts
        FOR SELECT
        USING (
          -- Caller must be an authenticated field-level officer
          auth.role() = 'authenticated'
          AND EXISTS (
            SELECT 1 FROM public.profiles p
            WHERE p.id = auth.uid()
              AND p.role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
              AND p.geo_lga IS NOT NULL
              AND TRIM(p.geo_lga) <> ''
              -- Alert's LGA matches officer's LGA (case- and space-insensitive)
              AND public.normalise_lga(p.geo_lga) = public.normalise_lga(alerts.geo_lga)
          )
        )
    $pol$;
    RAISE NOTICE 'Created policy: alerts_select_geo_lga_scoped';
  ELSE
    RAISE NOTICE 'Policy alerts_select_geo_lga_scoped already exists — skipped';
  END IF;
END $$;


-- ── Equivalent scoping for telemetry (track officers in-LGA only) ─────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'telemetry'
      AND policyname = 'telemetry_select_geo_lga_scoped'
  ) THEN
    EXECUTE $pol$
      CREATE POLICY "telemetry_select_geo_lga_scoped"
        ON public.telemetry
        FOR SELECT
        USING (
          auth.role() = 'authenticated'
          AND EXISTS (
            SELECT 1 FROM public.profiles caller
            WHERE caller.id = auth.uid()
              AND caller.role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
              AND caller.geo_lga IS NOT NULL
              AND TRIM(caller.geo_lga) <> ''
              AND EXISTS (
                SELECT 1 FROM public.profiles target
                WHERE target.id = telemetry.user_id
                  AND public.normalise_lga(target.geo_lga) = public.normalise_lga(caller.geo_lga)
              )
          )
        )
    $pol$;
    RAISE NOTICE 'Created policy: telemetry_select_geo_lga_scoped';
  ELSE
    RAISE NOTICE 'Policy telemetry_select_geo_lga_scoped already exists — skipped';
  END IF;
END $$;


-- ── Audit view: show which officers have no geo_lga (so you can fix them) ────

CREATE OR REPLACE VIEW public.officers_missing_geo_lga AS
SELECT
  id,
  full_name,
  role,
  geo_lga,
  badge_number,
  created_at
FROM public.profiles
WHERE role IN ('FIELD_OFFICER', 'WARD_OFFICER', 'LGA_OFFICER')
  AND (geo_lga IS NULL OR TRIM(geo_lga) = '')
ORDER BY created_at;

COMMENT ON VIEW public.officers_missing_geo_lga IS
  'Officers whose geo_lga is blank — they will not get the LGA-scoped RLS view '
  'until their profile is updated. Run: SELECT * FROM officers_missing_geo_lga;';


-- ── Verify ────────────────────────────────────────────────────────────────────

SELECT
  policyname,
  tablename,
  cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname IN (
    'alerts_select_geo_lga_scoped',
    'telemetry_select_geo_lga_scoped'
  );

COMMIT;
