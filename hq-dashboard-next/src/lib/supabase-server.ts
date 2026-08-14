import 'server-only';
import { createServerClient } from '@supabase/ssr';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { cookies } from 'next/headers';
import { publicEnv, serverEnv } from './env';

/**
 * Server-privileged Supabase access.
 *
 * `import 'server-only'` makes it a BUILD ERROR to import this module from a client
 * component, so the service_role key cannot silently reach the browser again.
 *
 * Clients are created lazily inside functions — never at module scope — because a
 * module-scope `createClient()` with missing env crashes `next build` during
 * page-data collection.
 */

/** Full-privilege client. Bypasses RLS — use only after authorising the caller. */
export function getSupabaseAdmin(): SupabaseClient {
  const { supabaseServiceRoleKey } = serverEnv();
  if (!supabaseServiceRoleKey) {
    throw new Error('[CONFIG] SUPABASE_SERVICE_ROLE_KEY is not configured.');
  }
  return createClient(publicEnv.supabaseUrl, supabaseServiceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

/** Request-scoped client that carries the caller's session cookies. */
export async function getSupabaseFromCookies(): Promise<SupabaseClient> {
  const cookieStore = await cookies();
  return createServerClient(publicEnv.supabaseUrl, publicEnv.supabaseAnonKey, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      // Route handlers may not mutate cookies here; session refresh is handled by proxy.ts.
      setAll: () => {},
    },
  });
}

export type Authorised = { ok: true; userId: string; role: string };
export type Unauthorised = { ok: false; status: 401 | 403; error: string };

/**
 * Authenticate the caller and check their profile role against `allowedRoles`.
 *
 * Every API route must call this before doing any work. Previously both routes
 * executed their full business logic for completely unauthenticated callers.
 */
export async function requireRole(allowedRoles: string[]): Promise<Authorised | Unauthorised> {
  const supabase = await getSupabaseFromCookies();
  const { data: { user }, error } = await supabase.auth.getUser();

  if (error || !user) {
    return { ok: false, status: 401, error: 'Authentication required' };
  }

  // Role is read with admin privileges so the check cannot be spoofed by permissive RLS.
  const admin = getSupabaseAdmin();
  const { data: profile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();

  const role = (profile?.role as string | undefined) ?? '';
  if (!role || !allowedRoles.includes(role)) {
    return { ok: false, status: 403, error: 'Insufficient privileges' };
  }
  return { ok: true, userId: user.id, role };
}

/**
 * Authenticate a NON-BROWSER caller carrying a Supabase access token as
 * `Authorization: Bearer <jwt>`.
 *
 * The mobile app is not a cookie client — it holds a Supabase session in the
 * Flutter SDK — so `requireRole()` above (which reads request cookies) can never
 * authorise it. Without this, the only way for the app to reach a privileged
 * backend operation was to hold the provider credential itself, which is exactly
 * what put `TERMII_API_KEY` inside the shipped APK (finding H-3).
 *
 * The token is verified by Supabase's auth server, not decoded locally: a JWT
 * this process merely parses proves nothing.
 *
 * No role check here on purpose. The routes that use it are ones ANY authenticated
 * citizen is entitled to invoke (raising their own SOS). Authorisation for those
 * comes from the route constraining WHAT can be done, not from the caller's rank.
 */
export async function requireUser(req: Request): Promise<Authorised | Unauthorised> {
  const header = req.headers.get('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';
  if (!token) {
    return { ok: false, status: 401, error: 'Authentication required' };
  }

  const admin = getSupabaseAdmin();
  const { data: { user }, error } = await admin.auth.getUser(token);
  if (error || !user) {
    return { ok: false, status: 401, error: 'Authentication required' };
  }

  const { data: profile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .maybeSingle();

  return { ok: true, userId: user.id, role: (profile?.role as string | undefined) ?? '' };
}

/** Roles permitted to trigger outbound dispatch / inter-agency escalation. */
export const COMMAND_ROLES = ['HQ_COMMAND', 'HQ_OFFICER', 'ADMIN', 'LGA_COMMAND'];
