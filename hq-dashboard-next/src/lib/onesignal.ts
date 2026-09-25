// One place that decides how this project talks to OneSignal.
//
// The three senders (this app's /api/push/dispatch, supabase/functions/
// notify-alert and supabase/functions/escalation-worker) disagreed: two sent
// `Authorization: Key ...` and one sent `Authorization: Basic ...` to the same
// v1 endpoint, so at most two of the three could ever have worked.
//
// `Key` is the scheme for current OneSignal REST API keys. Projects still
// holding a legacy key need `Basic`, so the scheme is an environment variable
// rather than a code change: set ONESIGNAL_AUTH_SCHEME=Basic.
export const ONESIGNAL_ENDPOINT = 'https://onesignal.com/api/v1/notifications';

export const oneSignalHeaders = (
  restKey: string,
  scheme: string,
): Record<string, string> => ({
  'Content-Type': 'application/json; charset=utf-8',
  Authorization: `${scheme} ${restKey}`,
});
