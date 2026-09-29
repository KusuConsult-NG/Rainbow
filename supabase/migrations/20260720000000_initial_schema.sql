-- ==============================================================================
-- OPERATION RAINBOW — SUPABASE POSTGRESQL SCHEMA MIGRATION
-- Copy and paste this script into your Supabase Dashboard -> SQL Editor -> Run
-- ==============================================================================

-- 1. PROFILES TABLE (Linked 1-to-1 with auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  phone TEXT UNIQUE,
  full_name TEXT,
  role TEXT NOT NULL DEFAULT 'CITIZEN', -- CITIZEN, RESPONDER, LGA_COMMAND, WARD_COMMAND, HQ_COMMAND
  tier TEXT DEFAULT 'UNKNOWN',          -- pu, ward, lga, unknown
  geo_lga TEXT,
  geo_ward TEXT,
  geo_pu TEXT,
  profile_complete BOOLEAN DEFAULT false,
  is_active BOOLEAN DEFAULT true,
  last_seen TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Automatic Profile Creation Trigger on Auth Signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
BEGIN
  INSERT INTO public.profiles (id, email, phone, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', 'User'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'CITIZEN')
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    phone = EXCLUDED.phone,
    updated_at = NOW();
  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 2. ALERTS TABLE
CREATE TABLE IF NOT EXISTS public.alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  local_id TEXT,
  type TEXT NOT NULL,                  -- SOS, INCIDENT, AI_VOICE_REPORT
  sub_type TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING', -- PENDING, DISPATCHED, ON_SITE, RESOLVED, CANCELLED
  severity TEXT DEFAULT 'MEDIUM',      -- LOW, MEDIUM, HIGH, CRITICAL
  description TEXT,
  reported_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  geo_lga TEXT,
  geo_ward TEXT,
  geo_pu TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  ai_summary TEXT,
  citizen_feedback TEXT,
  feedback_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TELEMETRY TABLE (Live Responder & SOS GPS)
CREATE TABLE IF NOT EXISTS public.telemetry (
  user_id UUID PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  mode TEXT NOT NULL,                   -- sos, responder
  status TEXT DEFAULT 'PATROLLING',
  battery INTEGER,
  network TEXT,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CHAT MESSAGES TABLE
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alert_id UUID REFERENCES public.alerts(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  sender_name TEXT,
  sender_role TEXT,
  message TEXT NOT NULL,
  media_url TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. SYSTEM ALERTS TABLE (Tactical Advisories)
CREATE TABLE IF NOT EXISTS public.system_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  severity TEXT DEFAULT 'HIGH',
  target_type TEXT DEFAULT 'ALL',
  target_value TEXT,
  is_active BOOLEAN DEFAULT true,
  created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.telemetry ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.system_alerts ENABLE ROW LEVEL SECURITY;

-- Profiles RLS
CREATE POLICY "Allow public read access to profiles" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Allow individual insert/update to own profile" ON public.profiles FOR ALL USING (auth.uid() = id);

-- Alerts RLS
CREATE POLICY "Allow authenticated users to read alerts" ON public.alerts FOR SELECT USING (auth.role() = 'authenticated' OR auth.role() = 'service_role');
CREATE POLICY "Allow authenticated users to insert alerts" ON public.alerts FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow authenticated users to update alerts" ON public.alerts FOR UPDATE USING (true);

-- Telemetry RLS
CREATE POLICY "Allow reading telemetry" ON public.telemetry FOR SELECT USING (true);
CREATE POLICY "Allow users to update own telemetry" ON public.telemetry FOR ALL USING (true);

-- Chat Messages RLS
CREATE POLICY "Allow reading chat messages" ON public.chat_messages FOR SELECT USING (true);
CREATE POLICY "Allow inserting chat messages" ON public.chat_messages FOR INSERT WITH CHECK (true);

-- System Alerts RLS
CREATE POLICY "Allow reading system alerts" ON public.system_alerts FOR SELECT USING (true);
CREATE POLICY "Allow service role to manage system alerts" ON public.system_alerts FOR ALL USING (true);

-- Enable Realtime for Alerts, Telemetry & Chat (idempotent)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.alerts;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.telemetry;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.system_alerts;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
