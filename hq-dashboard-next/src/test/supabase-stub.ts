/**
 * A stand-in for the browser Supabase client, for component tests.
 *
 * It records what a component asked for and answers from an in-memory table
 * map, so a test can assert the two things that actually matter for these
 * panels: that a write carried the right values, and that the list was
 * RE-READ afterwards. A panel that writes but does not re-read shows an
 * operator stale state, and the same action gets taken twice.
 *
 * The query builder is faked as a chainable thenable rather than a real
 * PostgREST client: `.select().order().limit()` returns `this` until awaited.
 * Filters are recorded, not applied — a test that needs filtering should set
 * the rows it expects back.
 */

export interface RecordedUpdate {
  table: string;
  values: Record<string, unknown>;
  eq: [string, unknown] | null;
}

export interface RecordedInsert {
  table: string;
  values: unknown;
}

export interface SupabaseStub {
  /** Pass this where the component expects `supabase`. */
  client: any;
  setRows(table: string, rows: unknown[]): void;
  setError(table: string, error: { message: string }): void;
  /** How many times the component read `table`. */
  selectCount(table: string): number;
  updates: RecordedUpdate[];
  inserts: RecordedInsert[];
  /** Resolves the next auth call with this. */
  authResult: { data: unknown; error: unknown };
}

type Result = { data: unknown; error: unknown };

export function makeSupabaseStub(): SupabaseStub {
  const rows = new Map<string, unknown[]>();
  const errors = new Map<string, { message: string }>();
  const selects = new Map<string, number>();
  const updates: RecordedUpdate[] = [];
  const inserts: RecordedInsert[] = [];

  const stub: SupabaseStub = {
    client: null,
    setRows: (t, r) => {
      rows.set(t, r);
      errors.delete(t);
    },
    setError: (t, e) => errors.set(t, e),
    selectCount: (t) => selects.get(t) ?? 0,
    updates,
    inserts,
    authResult: { data: { user: { id: 'stub-user' } }, error: null },
  };

  /**
   * A chainable thenable. Every unknown method returns the chain; awaiting it
   * runs `resolve`. `single`/`maybeSingle` unwrap the first row, matching
   * PostgREST.
   */
  function chain(resolve: () => Result, onCall?: (m: string, a: unknown[]) => void) {
    let unwrapSingle = false;
    const proxy: any = new Proxy(function () {} as any, {
      get(_t, prop) {
        if (prop === 'then') {
          return (ok: (v: Result) => unknown, fail?: (e: unknown) => unknown) => {
            let out = resolve();
            if (unwrapSingle) {
              const list = Array.isArray(out.data) ? out.data : [];
              out = { data: list.length ? list[0] : null, error: out.error };
            }
            return Promise.resolve(out).then(ok, fail);
          };
        }
        if (typeof prop !== 'string') return undefined;
        return (...args: unknown[]) => {
          if (prop === 'single' || prop === 'maybeSingle') unwrapSingle = true;
          onCall?.(prop, args);
          return proxy;
        };
      },
    });
    return proxy;
  }

  const resultFor = (table: string): Result => {
    const err = errors.get(table);
    if (err) return { data: null, error: err };
    return { data: rows.get(table) ?? [], error: null };
  };

  stub.client = {
    from(table: string) {
      return {
        select: (...args: unknown[]) => {
          selects.set(table, (selects.get(table) ?? 0) + 1);
          void args;
          // `eq` and `like` ARE applied. Without them a component nested
          // inside another (AgencyAccessManager inside AdminDirectory) sees
          // rows its query excludes, and the same record renders twice.
          const filters: Array<(row: any) => boolean> = [];
          return chain(
            () => {
              const base = resultFor(table);
              if (base.error || !Array.isArray(base.data)) return base;
              return {
                data: (base.data as any[]).filter((r) => filters.every((f) => f(r))),
                error: null,
              };
            },
            (m, a) => {
              if (m === 'eq') {
                filters.push((r) => r?.[a[0] as string] === a[1]);
              } else if (m === 'like' || m === 'ilike') {
                const col = a[0] as string;
                const pattern = String(a[1]);
                const rx = new RegExp(
                  `^${pattern.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/%/g, '.*')}$`,
                  m === 'ilike' ? 'i' : '',
                );
                filters.push((r) => rx.test(String(r?.[col] ?? '')));
              }
            },
          );
        },
        update: (values: Record<string, unknown>) => {
          const rec: RecordedUpdate = { table, values, eq: null };
          updates.push(rec);
          return chain(
            () => ({ data: null, error: null }),
            (m, a) => {
              if (m === 'eq') rec.eq = [a[0] as string, a[1]];
            },
          );
        },
        insert: (values: unknown) => {
          inserts.push({ table, values });
          return chain(() => ({ data: null, error: null }));
        },
        upsert: (values: unknown) => {
          inserts.push({ table, values });
          return chain(() => ({ data: null, error: null }));
        },
        delete: () => chain(() => ({ data: null, error: null })),
      };
    },
    auth: {
      signUp: async () => stub.authResult,
      signInWithPassword: async () => stub.authResult,
      getUser: async () => stub.authResult,
      getSession: async () => ({ data: { session: null }, error: null }),
      signOut: async () => ({ error: null }),
      onAuthStateChange: () => ({
        data: { subscription: { unsubscribe: () => {} } },
      }),
    },
    channel: () => ({
      on: function () {
        return this;
      },
      subscribe: function () {
        return this;
      },
      unsubscribe: () => {},
    }),
    removeChannel: () => {},
  };

  return stub;
}
