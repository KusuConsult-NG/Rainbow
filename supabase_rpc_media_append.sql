-- Run this in Supabase SQL Editor
-- Atomic array append for media_urls to prevent race conditions
CREATE OR REPLACE FUNCTION append_media_urls(alert_id UUID, new_urls TEXT[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE alerts
  SET
    media_urls = COALESCE(media_urls, ARRAY[]::text[]) || new_urls,
    updated_at = NOW()
  WHERE id = alert_id;
END;
$$;

GRANT EXECUTE ON FUNCTION append_media_urls(UUID, TEXT[]) TO authenticated;
