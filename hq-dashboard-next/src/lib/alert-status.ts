// Canonical incident status vocabulary, kept in step with the database.
//
// `OPEN_STATUSES` mirrors public.escalation_open_statuses() in
// supabase/migrations/phase6_escalation_engine.sql. The engine decides what is
// still open from that function; anything counting open incidents in the UI has
// to agree with it, or the dashboard and the escalation engine disagree about
// which incidents are live.
export const OPEN_STATUSES = [
  'PENDING',
  'OPEN',
  'ACTIVE',
  'DURESS',
  'DISPATCHED',
  'ACKNOWLEDGED',
  'ON_ROUTE',
  'ON_SITE',
  'IN_PROGRESS',
] as const;

export const CLOSED_STATUSES = ['RESOLVED', 'CLOSED', 'CANCELLED'] as const;

export type AlertStatus = (typeof OPEN_STATUSES)[number] | (typeof CLOSED_STATUSES)[number];

export const isOpenStatus = (status?: string | null): boolean =>
  !!status && (OPEN_STATUSES as readonly string[]).includes(status.toUpperCase());
