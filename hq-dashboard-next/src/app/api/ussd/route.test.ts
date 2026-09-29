// The USSD gateway callback.
//
// The menu itself is tested as a pure reducer in lib/ussd-menu.test.ts. What is
// tested here is everything the reducer deliberately does not know about: the
// gateway secret, the two body encodings, session state across screens, a retry
// of a keypress already answered, and — the one that matters most — what a
// caller is told when the filing fails.
import { beforeEach, describe, expect, it, vi } from 'vitest';

interface Rpc { fn: string; args: Record<string, unknown> }

const rpcCalls: Rpc[] = [];
const inserts: { table: string; row: Record<string, unknown> }[] = [];
const updates: { table: string; row: Record<string, unknown> }[] = [];
const createdUsers: Record<string, unknown>[] = [];

/** The session row the mock returns from `.maybeSingle()`, or null. */
let sessionRow: Record<string, unknown> | null = null;
let callerRows: unknown[] = [];
let lastReportRows: unknown[] = [];
let fileRows: unknown[] = [{ reference: 'R4K2M9', alert_id: 'a-1', already_filed: false }];
let fileError: { message: string } | null = null;
let sessionReadError: { message: string } | null = null;
/** Force a named RPC to answer with an error, without re-mocking the module. */
let rpcErrors: Record<string, { message: string }> = {};
/** Answers for RPCs beyond the four the main mock knows. */
let extraAnswers: Record<string, { data: unknown; error: unknown }> = {};
let createUserResult: { data: { user: { id: string } } | null; error: unknown } =
  { data: { user: { id: 'new-user-1' } }, error: null };

vi.mock('@/lib/supabase-server', () => ({
  getSupabaseAdmin: () => ({
    rpc: async (fn: string, args: Record<string, unknown>) => {
      rpcCalls.push({ fn, args });
      if (rpcErrors[fn]) return { data: null, error: rpcErrors[fn] };
      if (fn === 'ussd_caller') return { data: callerRows, error: null };
      if (fn === 'ussd_last_report') return { data: lastReportRows, error: null };
      if (fn === 'ussd_file_report') return { data: fileRows, error: fileError };
      if (extraAnswers[fn]) return extraAnswers[fn];
      return { data: null, error: null };
    },
    from: (table: string) => ({
      select: () => ({
        eq: () => ({
          maybeSingle: async () => ({ data: sessionRow, error: sessionReadError }),
        }),
      }),
      insert: async (row: Record<string, unknown>) => {
        inserts.push({ table, row });
        return { error: null };
      },
      update: (row: Record<string, unknown>) => ({
        eq: async () => {
          updates.push({ table, row });
          return { error: null };
        },
      }),
    }),
    auth: {
      admin: {
        createUser: async (row: Record<string, unknown>) => {
          createdUsers.push(row);
          return createUserResult;
        },
      },
    },
  }),
}));

const SECRET = 'a-long-shared-ussd-secret';

async function post(
  body: Record<string, string>,
  opts: { headers?: Record<string, string>; form?: boolean } = {},
) {
  const { POST } = await import('./route');
  const headers: Record<string, string> = {
    'x-gateway-secret': SECRET,
    ...(opts.headers ?? {}),
  };
  let payload: string;
  if (opts.form) {
    headers['content-type'] = 'application/x-www-form-urlencoded';
    payload = new URLSearchParams(body).toString();
  } else {
    headers['content-type'] = 'application/json';
    payload = JSON.stringify(body);
  }
  const res = await POST(
    new Request('http://localhost/api/ussd', { method: 'POST', headers, body: payload }) as never,
  );
  return { res, text: await res.text() };
}

const filed = () => rpcCalls.filter(c => c.fn === 'ussd_file_report');
const answersFor = (fn: string, data: unknown) => {
  extraAnswers[fn] = { data, error: null };
};

beforeEach(() => {
  vi.resetModules();
  rpcCalls.length = 0;
  inserts.length = 0;
  updates.length = 0;
  createdUsers.length = 0;
  sessionRow = null;
  callerRows = [];
  lastReportRows = [];
  fileRows = [{ reference: 'R4K2M9', alert_id: 'a-1', already_filed: false }];
  fileError = null;
  sessionReadError = null;
  rpcErrors = {};
  extraAnswers = {};
  createUserResult = { data: { user: { id: 'new-user-1' } }, error: null };
  process.env.USSD_GATEWAY_SECRET = SECRET;
  delete process.env.USSD_REPLY_FORMAT;
  vi.spyOn(console, 'warn').mockImplementation(() => {});
  vi.spyOn(console, 'error').mockImplementation(() => {});
});

describe('getting in', () => {
  it('refuses a request with no secret, and files nothing', async () => {
    const { text } = await post({ sessionId: 'S1', phoneNumber: '08030001111' }, { headers: { 'x-gateway-secret': '' } });
    expect(text).toContain('Service unavailable');
    expect(filed()).toHaveLength(0);
  });

  it('refuses a wrong secret', async () => {
    const { text } = await post({ sessionId: 'S1', phoneNumber: '08030001111' }, { headers: { 'x-gateway-secret': 'nope' } });
    expect(text).toContain('Service unavailable');
  });

  it('refuses to run at all when no secret is configured', async () => {
    // An open USSD endpoint lets anybody inject emergencies with a forged
    // MSISDN, which removes the only thing this channel's trust rests on.
    delete process.env.USSD_GATEWAY_SECRET;
    const { text } = await post({ sessionId: 'S1', phoneNumber: '08030001111' });
    expect(text).toContain('Service unavailable');
    expect(rpcCalls).toHaveLength(0);
  });

  it('answers 200 even when it refuses', async () => {
    // A gateway that sees a non-2xx shows the handset a carrier error page with
    // none of our words on it.
    const { res } = await post({ sessionId: 'S1', phoneNumber: '08030001111' }, { headers: { 'x-gateway-secret': 'nope' } });
    expect(res.status).toBe(200);
  });

  it('always names an alternative when it cannot help', async () => {
    // A person left on a dead menu presses keys until the session times out.
    const { text } = await post({ sessionId: 'S1', phoneNumber: '08030001111' }, { headers: { 'x-gateway-secret': 'nope' } });
    expect(text).toContain('112');
    expect(text.startsWith('END ')).toBe(true);
  });
});

describe('reading the callback', () => {
  it('accepts a form-encoded body', async () => {
    // Africa's Talking and several carrier integrations post a form. Reading
    // only JSON would fail every single callback.
    const { text } = await post({ sessionId: 'S2', phoneNumber: '08030001111' }, { form: true });
    expect(text).toContain('Operation Rainbow');
  });

  it('accepts a JSON body', async () => {
    const { text } = await post({ sessionId: 'S3', phoneNumber: '08030001111' });
    expect(text).toContain('Operation Rainbow');
  });

  it('refuses a shape it does not recognise, and says which keys arrived', async () => {
    // This presents as "the menu restarts every time" with nothing to go on, so
    // the log has to carry the keys.
    const err = vi.spyOn(console, 'error');
    const { text } = await post({ dialogueRef: 'X', callerId: '0803', keys: '1' });
    expect(text).toContain('Service unavailable');
    expect(err.mock.calls.flat().join(' ')).toContain('dialogueRef');
  });

  it('opens with the root menu and keeps the session open', async () => {
    const { text } = await post({ sessionId: 'S4', phoneNumber: '08030001111' });
    expect(text.startsWith('CON ')).toBe(true);
    expect(text).toContain('1. EMERGENCY');
    expect(inserts.some(i => i.table === 'ussd_sessions')).toBe(true);
  });
});

describe('a retry of a keypress already answered', () => {
  it('replays the cached screen without re-running anything', async () => {
    sessionRow = {
      state: { step: 'EMERGENCY_KIND', emergency: true, page: 0 },
      last_input: '1',
      last_screen: 'CACHED SCREEN',
      filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S5', phoneNumber: '08030001111', text: '1' });
    expect(text).toBe('CON CACHED SCREEN');
    // Nothing was looked up and nothing was filed.
    expect(rpcCalls).toHaveLength(0);
  });

  it('replays a terminal screen as terminal', async () => {
    // Replaying the "SENT" screen with CON would leave the caller on a dead
    // session waiting for a menu that is never coming.
    sessionRow = {
      state: { step: 'DONE', emergency: true, page: 0 },
      last_input: '1',
      last_screen: 'SENT TO COMMAND.\nRef R4K2M9',
      filed_alert: 'a-1',
    };
    const { text } = await post({ sessionId: 'S6', phoneNumber: '08030001111', text: '1' });
    expect(text.startsWith('END ')).toBe(true);
    expect(text).toContain('R4K2M9');
    expect(filed()).toHaveLength(0);
  });

  it('does NOT replay when the keypress is a new one', async () => {
    sessionRow = {
      state: { step: 'EMERGENCY_KIND', emergency: true, page: 0 },
      last_input: '1',
      last_screen: 'CACHED SCREEN',
      filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S7', phoneNumber: '08030001111', text: '2' });
    expect(text).not.toContain('CACHED SCREEN');
  });
});

describe('filing a report', () => {
  const KNOWN = [{ user_id: 'u-1', role: 'CITIZEN', geo_lga: 'JOS NORTH', geo_ward: 'ABBA NA SHEHU' }];

  it('files with the caller’s posting and the callback answer', async () => {
    callerRows = KNOWN;
    sessionRow = {
      state: { step: 'CALLBACK', emergency: true, kind: 'Kidnap - Immediate Abduction',
               lga: 'JOS NORTH', ward: 'ABBA NA SHEHU', page: 0 },
      // The keypress that brought them TO the callback screen. Setting this to
      // the one being sent now makes the request a retry by definition, and the
      // cached screen is replayed instead — which is the cache working, and
      // silently turned four of these tests into assertions about nothing.
      last_input: '4',
      last_screen: 'earlier screen',
      filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S8', phoneNumber: '08030001111', text: '1' });

    expect(filed()).toHaveLength(1);
    expect(filed()[0].args).toMatchObject({
      p_session_id: 'S8',
      p_msisdn: '+2348030001111',
      p_reporter: 'u-1',
      p_type: 'Kidnap - Immediate Abduction',
      p_emergency: true,
      p_lga: 'JOS NORTH',
      p_callback: true,
    });
    // Not terminal any more: the report is filed and the next screen asks for a
    // landmark. The caller already has their reference, so the session staying
    // open costs them nothing.
    expect(text.startsWith('CON ')).toBe(true);
    expect(text).toContain('R4K2M9');
    expect(text.toLowerCase()).toContain('landmark');
  });

  it('does not create an account for a caller who already has one', async () => {
    callerRows = KNOWN;
    sessionRow = {
      state: { step: 'CALLBACK', emergency: true, kind: 'Fire - Building Fire', page: 0 },
      last_input: '4', last_screen: 'x', filed_alert: null,
    };
    await post({ sessionId: 'S9', phoneNumber: '08030001111', text: '2' });
    expect(createdUsers).toHaveLength(0);
  });

  it('registers an unknown number ON THE FILING REQUEST, not before', async () => {
    // Somebody who dials, looks at the menu and hangs up should leave no
    // account behind.
    callerRows = [];
    await post({ sessionId: 'S10', phoneNumber: '08030001111' });
    expect(createdUsers).toHaveLength(0);

    sessionRow = {
      state: { step: 'CALLBACK', emergency: true, kind: 'Fire - Building Fire',
               lga: 'BOKKOS', ward: 'BOKKOS', page: 0 },
      last_input: '4', last_screen: 'x', filed_alert: null,
    };
    await post({ sessionId: 'S10', phoneNumber: '08030001111', text: '2' });
    expect(createdUsers).toHaveLength(1);
    expect(createdUsers[0]).toMatchObject({ phone: '2348030001111', phone_confirm: true });
    expect(inserts.some(i => i.table === 'profiles'
      && i.row.role === 'CITIZEN' && i.row.geo_lga === 'BOKKOS')).toBe(true);
  });

  it('still files when self-registration fails', async () => {
    // An unattributed emergency is worth far more than a tidy reported_by, and
    // the MSISDN on the alert keeps the reachable number regardless.
    callerRows = [];
    createUserResult = { data: null, error: { message: 'auth is down' } };
    sessionRow = {
      state: { step: 'CALLBACK', emergency: true, kind: 'Fire - Building Fire', page: 0 },
      last_input: '4', last_screen: 'x', filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S11', phoneNumber: '08030001111', text: '1' });
    expect(filed()).toHaveLength(1);
    expect(filed()[0].args.p_reporter).toBeNull();
    expect(filed()[0].args.p_msisdn).toBe('+2348030001111');
    expect(text).toContain('R4K2M9');
  });

  it('tells the caller NOT SENT when the filing fails, with no reference', async () => {
    // The most important assertion in this file. Somebody who believes their
    // report went through stops trying.
    fileError = { message: 'deadlock detected' };
    fileRows = [];
    sessionRow = {
      state: { step: 'CALLBACK', emergency: true, kind: 'Kidnap - Immediate Abduction', page: 0 },
      last_input: '4', last_screen: 'x', filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S12', phoneNumber: '08030001111', text: '1' });
    expect(text).toContain('NOT SENT');
    expect(text).toContain('112');
    expect(text).not.toMatch(/Ref R/);
    expect(text.startsWith('END ')).toBe(true);
  });

  it('does not claim SENT when the database returned no row', async () => {
    // No error and no row — a refusal. It must not read as success.
    fileError = null;
    fileRows = [];
    sessionRow = {
      state: { step: 'CALLBACK', emergency: false, kind: 'Theft - Property Crime', page: 0 },
      last_input: '4', last_screen: 'x', filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S13', phoneNumber: '08030001111', text: '2' });
    expect(text).toContain('NOT SENT');
  });

  it('reports the same reference when the database says it was a retry', async () => {
    fileRows = [{ reference: 'RAAAAA', alert_id: 'a-9', already_filed: true }];
    sessionRow = {
      state: { step: 'CALLBACK', emergency: true, kind: 'Fire - Building Fire', page: 0 },
      last_input: '4', last_screen: 'x', filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S14', phoneNumber: '08030001111', text: '1' });
    expect(text).toContain('RAAAAA');
  });
});

describe('the landmark turn', () => {
  const AT_LANDMARK = {
    state: { step: 'LANDMARK', emergency: true, kind: 'Kidnap - Immediate Abduction', page: 0 },
    last_input: '1',
    last_screen: 'SENT TO COMMAND. Ref R4K2M9',
    filed_alert: 'a-1',
  };

  it('attaches what the caller typed and closes the dialogue', async () => {
    sessionRow = AT_LANDMARK;
    answersFor('ussd_add_landmark', [{ reference: 'R4K2M9', alert_id: 'a-1' }]);
    const { text } = await post({
      sessionId: 'S30', phoneNumber: '08030001111', text: 'behind Bukuru market',
    });
    const call = rpcCalls.find(c => c.fn === 'ussd_add_landmark');
    expect(call!.args).toEqual({ p_session_id: 'S30', p_landmark: 'behind Bukuru market' });
    expect(text.startsWith('END ')).toBe(true);
    expect(text).toContain('Keep this phone on');
  });

  it('does NOT report a failure when the landmark could not be attached', async () => {
    // The report is already filed and the caller has their reference. Telling
    // them something went wrong would invite them to dial again and raise a
    // SECOND incident for the same event.
    sessionRow = AT_LANDMARK;
    rpcErrors = { ussd_add_landmark: { message: 'boom' } };
    const { text } = await post({
      sessionId: 'S31', phoneNumber: '08030001111', text: 'behind the market',
    });
    expect(text).not.toContain('NOT SENT');
    expect(text).toContain('Keep this phone on');
    expect(text.startsWith('END ')).toBe(true);
  });

  it('closes the dialogue on a skip without calling the database', async () => {
    sessionRow = AT_LANDMARK;
    const { text } = await post({ sessionId: 'S32', phoneNumber: '08030001111', text: '0' });
    expect(rpcCalls.some(c => c.fn === 'ussd_add_landmark')).toBe(false);
    expect(text.startsWith('END ')).toBe(true);
    expect(text).toContain('Do not reply by SMS');
  });

  it('files nothing on the landmark turn', async () => {
    // The one thing that would be catastrophic here: a second alert for the same
    // emergency because the landmark turn re-ran the filing.
    sessionRow = AT_LANDMARK;
    answersFor('ussd_add_landmark', [{ reference: 'R4K2M9', alert_id: 'a-1' }]);
    await post({ sessionId: 'S33', phoneNumber: '08030001111', text: 'the junction' });
    expect(filed()).toHaveLength(0);
  });
});

describe('the status screen', () => {
  it('reads the caller’s last report back', async () => {
    lastReportRows = [{
      reference: 'R4K2M9',
      kind: 'Kidnap - Immediate Abduction',
      status: 'PENDING',
      age_minutes: 12,
    }];
    sessionRow = { state: { step: 'ROOT', emergency: false, page: 0 }, last_input: '', last_screen: 'root', filed_alert: null };
    const { text } = await post({ sessionId: 'S15', phoneNumber: '08030001111', text: '3' });
    expect(text).toContain('R4K2M9');
    expect(text).toContain('12 min ago');
    expect(text.startsWith('END ')).toBe(true);
  });

  it('says there is no report when the number has none', async () => {
    lastReportRows = [];
    sessionRow = { state: { step: 'ROOT', emergency: false, page: 0 }, last_input: '', last_screen: 'root', filed_alert: null };
    const { text } = await post({ sessionId: 'S16', phoneNumber: '08030001111', text: '3' });
    expect(text).toContain('No report found');
  });

  it('does not say "no report" when the LOOKUP failed', async () => {
    // Telling somebody their emergency was never recorded is a different and
    // much worse claim than "we could not read it just now".
    //
    // Driven by a flag on the one mock rather than a second vi.doMock: importing
    // @/lib/supabase-server from inside a test pulls in `server-only`, which
    // throws and then poisons every test that runs after it.
    rpcErrors = { ussd_last_report: { message: 'boom' } };
    sessionRow = {
      state: { step: 'ROOT', emergency: false, page: 0 },
      last_input: '', last_screen: 'root', filed_alert: null,
    };
    const { text } = await post({ sessionId: 'S17', phoneNumber: '08030001111', text: '3' });
    expect(text).toContain('Could not check');
    expect(text).not.toContain('No report found');
  });
});

describe('when the session store is unreachable', () => {
  it('does not guess at a menu, and names an alternative', async () => {
    sessionReadError = { message: 'connection reset' };
    const { text } = await post({ sessionId: 'S18', phoneNumber: '08030001111', text: '1' });
    expect(text).toContain('Service unavailable');
    expect(text).toContain('112');
    expect(filed()).toHaveLength(0);
  });
});

describe('the reply format', () => {
  it('uses the JSON convention when configured to', async () => {
    process.env.USSD_REPLY_FORMAT = 'JSON';
    vi.resetModules();
    const { text, res } = await post({ sessionId: 'S19', phoneNumber: '08030001111' });
    expect(res.headers.get('content-type')).toContain('application/json');
    expect(JSON.parse(text)).toMatchObject({ sessionState: 'CONTINUE' });
  });
});

describe('the session record', () => {
  it('saves the state, the input and the screen for the next turn', async () => {
    await post({ sessionId: 'S20', phoneNumber: '08030001111' });
    const saved = updates.find(u => u.table === 'ussd_sessions');
    expect(saved).toBeDefined();
    expect(saved!.row.last_input).toBe('');
    expect(String(saved!.row.last_screen)).toContain('Operation Rainbow');
    expect(saved!.row.state).toMatchObject({ step: 'ROOT' });
  });

  it('takes the latest keypress from an accumulated path', async () => {
    // The aggregator sent '1*2'; the reducer must be given '2'.
    sessionRow = {
      state: { step: 'EMERGENCY_KIND', emergency: true, page: 0 },
      last_input: '1', last_screen: 'kinds', filed_alert: null,
    };
    await post({ sessionId: 'S21', phoneNumber: '08030001111', text: '1*2' });
    const saved = updates.find(u => u.table === 'ussd_sessions');
    expect(saved!.row.last_input).toBe('2');
  });
});
