/**
 * The Authorization header for OneSignal, decided in one place.
 *
 * ## The defect
 *
 * Three call sites sent the SAME credential — `ONESIGNAL_REST_API_KEY` — under
 * two different schemes:
 *
 *     api/notify/drain/route.ts        Authorization: Basic <key>
 *     api/push/dispatch/route.ts       Authorization: Basic <key>
 *     supabase/functions/notify-alert  Authorization: Key <key>
 *
 * One key, two schemes, so at least one of those three has never authenticated.
 * And `api/push/dispatch` returned `{ success: true, notifiedCount: N }` without
 * looking at `response.ok` — so a 401 from OneSignal was reported to the console
 * as N notifications delivered. That is why nobody would ever have found out:
 * the one path most likely to be broken was also the one that could not report
 * being broken.
 *
 * ## Why this is not a constant
 *
 * OneSignal has two generations of credential and they do not take the same
 * scheme: the legacy REST API key and the newer `os_v2_*` keys. Which one a
 * deployment holds depends on when its app was provisioned, and this code cannot
 * see the OneSignal dashboard.
 *
 * So rather than assert a scheme — the mistake that produced the split above —
 * this derives it from the key's own shape, lets the operator override it, and
 * RETRIES THE OTHER SCHEME ONCE on an authentication failure, logging which one
 * worked. A deployment with the wrong guess self-corrects on its first push and
 * says in the log exactly what to set to remove the extra round trip.
 *
 * That is worth one retry on one request. Never finding out is worth nothing.
 */

export type OneSignalScheme = 'Basic' | 'Key';

/**
 * Which scheme a key most likely wants.
 *
 * `os_v2_`-prefixed credentials are the newer generation and take `Key`.
 * Anything else is treated as a legacy REST API key and takes `Basic`. This is a
 * STARTING GUESS, not a claim — `authAttempts()` below covers being wrong.
 */
export function schemeForKey(key: string): OneSignalScheme {
  return key.trim().startsWith('os_v2_') ? 'Key' : 'Basic';
}

/**
 * The schemes to try, in order.
 *
 * An explicit `ONESIGNAL_AUTH_SCHEME` is honoured and tried FIRST, but the other
 * is still kept as a fallback: an operator who sets it wrongly should get a
 * delivered notification and a log line telling them so, not silence.
 *
 * Returns one entry when the key is empty, because there is nothing to try.
 */
export function authAttempts(
  key: string,
  configured?: string | null,
): OneSignalScheme[] {
  if (!key.trim()) return [];
  const forced = (configured ?? '').trim();
  const first: OneSignalScheme | null =
    forced.toLowerCase() === 'basic' ? 'Basic'
      : forced.toLowerCase() === 'key' ? 'Key'
        : null;
  const guess = first ?? schemeForKey(key);
  const other: OneSignalScheme = guess === 'Basic' ? 'Key' : 'Basic';
  return [guess, other];
}

export function authHeader(scheme: OneSignalScheme, key: string): string {
  return `${scheme} ${key.trim()}`;
}

/** Whether a response means "your credential was not accepted". */
export function isAuthFailure(status: number): boolean {
  return status === 401 || status === 403;
}

export interface PushOutcome {
  ok: boolean;
  status: number;
  /** The scheme that was accepted, when one was. */
  scheme?: OneSignalScheme;
  /** OneSignal's parsed body, for the caller's log — never for the operator. */
  body?: unknown;
  /** Set when nothing worked. Safe to show an operator. */
  error?: string;
}

/**
 * POST a notification, trying the fallback scheme once if the first is refused.
 *
 * `fetchImpl` is injected so this is testable without a network, and because the
 * Deno edge function needs the same logic against its own fetch.
 */
export async function postNotification(
  key: string,
  payload: unknown,
  opts: {
    configuredScheme?: string | null;
    url?: string;
    fetchImpl?: typeof fetch;
    log?: (msg: string) => void;
  } = {},
): Promise<PushOutcome> {
  const url = opts.url ?? 'https://onesignal.com/api/v1/notifications';
  const doFetch = opts.fetchImpl ?? fetch;
  const log = opts.log ?? ((m: string) => console.warn(m));
  const attempts = authAttempts(key, opts.configuredScheme);

  if (attempts.length === 0) {
    return { ok: false, status: 0, error: 'No OneSignal key is configured.' };
  }

  let last: PushOutcome = { ok: false, status: 0, error: 'No attempt was made.' };

  for (let i = 0; i < attempts.length; i += 1) {
    const scheme = attempts[i];
    let res: Response;
    try {
      res = await doFetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          Authorization: authHeader(scheme, key),
        },
        body: JSON.stringify(payload),
      });
    } catch (e) {
      // A transport failure is not an auth failure, so trying the other scheme
      // would just be a second doomed request.
      return { ok: false, status: 0, error: `Could not reach OneSignal: ${String(e)}` };
    }

    let body: unknown;
    try {
      body = await res.json();
    } catch {
      body = null;
    }

    if (res.ok) {
      if (i > 0) {
        // The fallback worked, which means the configured or guessed scheme was
        // wrong. Said loudly and with the remedy, because the alternative is a
        // permanent extra round trip nobody ever notices.
        log(
          `[ONESIGNAL] authenticated with "${scheme}" after "${attempts[0]}" was `
          + `refused. Set ONESIGNAL_AUTH_SCHEME=${scheme} to skip the retry.`,
        );
      }
      return { ok: true, status: res.status, scheme, body };
    }

    last = {
      ok: false,
      status: res.status,
      body,
      error: `OneSignal refused the notification (HTTP ${res.status}).`,
    };

    // Only an auth failure is worth retrying under the other scheme. A 400 is a
    // bad payload and a 429 is a rate limit; sending either again immediately
    // helps nobody.
    if (!isAuthFailure(res.status)) return last;
  }

  return {
    ...last,
    error:
      'OneSignal rejected the credential under both authentication schemes. '
      + 'Check ONESIGNAL_REST_API_KEY.',
  };
}
