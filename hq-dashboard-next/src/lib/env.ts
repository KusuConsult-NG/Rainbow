/**
 * Centralised, validated environment access.
 *
 * Why this file exists:
 *   Previously each module read `process.env.X || '<hardcoded-literal>'`. That pattern
 *   has two failure modes that bit this codebase:
 *     1. A non-NEXT_PUBLIC var is `undefined` in the browser, so the `||` fallback
 *        becomes the operative value AND the literal is emitted into the client bundle.
 *        That is how the Supabase service_role key shipped to every visitor of /login.
 *     2. A missing variable degrades silently into a wrong-but-plausible default
 *        instead of failing loudly at startup.
 *
 * Rules enforced here:
 *   - No secret ever has a hardcoded fallback.
 *   - Server-only secrets are read through `serverEnv()`, which throws if imported
 *     into a browser bundle.
 *   - Public config is explicit about being public.
 */

/** Values that are safe to ship to the browser (Supabase anon key is public by design). */
export const publicEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? '',
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '',
};

export function assertPublicEnv(): void {
  const missing: string[] = [];
  if (!publicEnv.supabaseUrl) missing.push('NEXT_PUBLIC_SUPABASE_URL');
  if (!publicEnv.supabaseAnonKey) missing.push('NEXT_PUBLIC_SUPABASE_ANON_KEY');
  if (missing.length) {
    throw new Error(
      `[CONFIG] Missing required public environment variables: ${missing.join(', ')}. ` +
        `Copy .env.example to .env.local and fill it in.`
    );
  }
}

/**
 * Server-only secrets. Throws if reached from client code, which turns a silent
 * credential leak into a loud build/runtime failure.
 */
export function serverEnv() {
  if (typeof window !== 'undefined') {
    throw new Error('[CONFIG] serverEnv() must never be called from client code.');
  }
  return {
    supabaseServiceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY ?? '',
    termiiApiKey: process.env.TERMII_API_KEY ?? '',
    termiiSenderId: process.env.TERMII_SENDER_ID ?? 'RainbowHQ',
    // Destination for citizen SOS escalation SMS. Deliberately server-side and
    // NOT client-supplied: /api/sos/dispatch-sms would otherwise be an
    // authenticated open SMS relay billed to this Termii account.
    sosDispatchPhone: process.env.SOS_DISPATCH_PHONE ?? '',
    // NOT NEXT_PUBLIC_. It was, and `NEXT_PUBLIC_*` is inlined into the client
    // bundle, so any deployment that set it served the Gemini key to every
    // dashboard visitor. Read only by /api/ai/analyze.
    geminiApiKey: process.env.GEMINI_API_KEY ?? '',
    oneSignalAppId: process.env.ONESIGNAL_APP_ID ?? '',
    oneSignalRestKey: process.env.ONESIGNAL_REST_API_KEY ?? '',
    webhookSecret: process.env.RAINBOW_WEBHOOK_SECRET ?? '',
  };
}
