-- ============================================================================
-- OPERATION RAINBOW — INCIDENT MEDIA STORAGE
--
-- The mobile app uploads incident photos, video and voice reports to the
-- Supabase Storage bucket `incident-media` when Cloudinary is unavailable
-- (lib/services/alert_service.dart, lib/services/sync_service.dart), and both
-- apps display them through public URLs. Nothing in this repository created the
-- bucket or any policy on storage.objects. Storage RLS is enabled by default and
-- deny-all without policies, so on a fresh project every fallback upload fails,
-- and on production whatever was clicked together in the dashboard is
-- undocumented and unreviewed.
--
-- WHAT THIS SETS
--   * The bucket exists, is public (the apps read via getPublicUrl), accepts
--     only image/video/audio, and caps objects at 50 MB — the per-object limit
--     of the Supabase Free plan, so a larger setting would be silently lower.
--   * Any signed-in user may UPLOAD into it. Uploads are evidence from the
--     field, and the reporter is often a citizen.
--   * Nobody may UPDATE or DELETE through the API roles. Evidence is
--     append-only; removal is a service-role operation with an audit trail.
--   * Listing the bucket through the API is limited to staff. The bucket being
--     public means an object is readable BY ITS URL; it does not mean the
--     bucket may be enumerated, which would hand every piece of evidence to
--     anyone with the anon key.
--
-- Object URLs are unguessable (millisecond timestamp plus a random id) but not
-- secret: anyone who has one can open it. A private bucket with signed URLs
-- would be stronger, and is noted as a follow-up in E2E_AUDIT_REPORT.md; it
-- needs every media renderer in both apps changed first.
--
-- Guarded by existence so a vanilla PostgreSQL replica (the CI harness ships a
-- storage shim) and Supabase both accept it. Idempotent: safe to re-run.
-- ============================================================================

DO $storage$
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR to_regclass('storage.objects') IS NULL THEN
    RAISE NOTICE 'no storage schema in this database; skipping incident-media setup';
    RETURN;
  END IF;

  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES ('incident-media', 'incident-media', true, 52428800,
          ARRAY['image/*', 'video/*', 'audio/*'])
  ON CONFLICT (id) DO UPDATE
    SET public             = EXCLUDED.public,
        file_size_limit    = EXCLUDED.file_size_limit,
        allowed_mime_types = EXCLUDED.allowed_mime_types;

  -- Replace, never accumulate: PERMISSIVE policies OR together, so a stale
  -- wider policy left in place would silently win.
  DROP POLICY IF EXISTS "incident_media_upload"      ON storage.objects;
  DROP POLICY IF EXISTS "incident_media_staff_list"  ON storage.objects;

  CREATE POLICY "incident_media_upload" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'incident-media');

  CREATE POLICY "incident_media_staff_list" ON storage.objects
    FOR SELECT TO authenticated
    USING (bucket_id = 'incident-media' AND public.is_staff());

  -- No UPDATE / DELETE policy on purpose (see header).
END $storage$;
