import { createBrowserClient } from '@supabase/ssr';
import { createClient } from '@supabase/supabase-js';
import { publicEnv, assertPublicEnv } from './env';

/**
 * Client-safe Supabase access ONLY.
 *
 * This module is imported by `'use client'` components, so everything in it is
 * bundled for the browser. Never add a service_role client here — it will be
 * shipped to every visitor. Server-privileged access lives in `supabase-server.ts`,
 * which is import-guarded against client bundles.
 */
assertPublicEnv();

export const supabase =
  typeof window !== 'undefined'
    ? createBrowserClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey)
    : createClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey);
