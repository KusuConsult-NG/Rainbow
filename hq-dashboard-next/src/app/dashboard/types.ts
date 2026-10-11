/**
 * The alert shape the console works with.
 *
 * Lifted out of page.tsx so pure logic (src/lib/alert-display.ts) can be
 * imported and tested without dragging a 3,000-line client component — and its
 * whole dependency tree — into a unit test.
 *
 * Note both coordinate spellings. The database stores `latitude`/`longitude`;
 * LiveMap reads `lat`/`lng`; the page maps across (`lat: d.latitude ?? d.lat`).
 * Getting that wrong is what C-5 was about, so both are kept visible here
 * rather than quietly normalised.
 *
 * `reportedBy` and `reportedAt` USED to be declared here, alongside the real
 * `reported_by` and `created_at`. They are Firebase-era names: PostgREST never
 * returns a camelCase key, so every read of them was `undefined` and every
 * `alert.created_at || alert.reportedAt` fallback was dead code that made the
 * live one look optional. Declaring a field the database cannot supply is how
 * the map came to show no reporter and no time at all. They are gone; if a
 * value is missing now, it is missing in the row.
 */
export interface Alert {
  id: string;
  /** Set by clusterAlerts: every report folded into this card, this one included. */
  member_ids?: string[];
  /** Set by clusterAlerts: how many reports this card stands for. */
  witness_count?: number;
  local_id?: string;
  type?: string;
  sub_type?: string;

  /**
   * The reporting category, e.g. 'Kidnap'. A STORED GENERATED column over
   * `split_part(type, ' - ', 1)` — the database derives it, nothing writes it,
   * so it cannot drift from `type`. Optional because a console can be running
   * against a database the migration has not reached yet; `categoryOf` in
   * alert-category.ts falls back to deriving the same value.
   */
  category?: string | null;
  description?: string;
  /**
   * `ESCALATED` and `IN_PROGRESS` are here because src/lib/alert-actions.ts
   * WRITES them (escalateAlert and acknowledgeAlert), and the staging fixtures
   * carry an ESCALATED row. They were missing from this union while the console
   * that defines it was producing them, so any code switching exhaustively on a
   * status silently had no branch for two of the ten.
   */
  status:
    | 'PENDING'
    | 'DISPATCHED'
    | 'ACKNOWLEDGED'
    | 'IN_PROGRESS'
    | 'ON_ROUTE'
    | 'ON_SITE'
    | 'ESCALATED'
    | 'RESOLVED'
    | 'DURESS'
    | 'CANCELLED';
  /**
   * When the reporting handset signed out while this incident was still open.
   *
   * Tracking continues regardless — a duress PIN deliberately leaves it
   * running, and the lock screen's sign-out needs no code, so this is the one
   * path somebody other than the reporter can reach. The column exists so an
   * operator can tell "the app is gone" from "the battery died", which a gap in
   * the track cannot. See `20261020000000`.
   *
   * Optional, because a console can be running against a database the
   * migration has not reached yet.
   */
  device_signed_out_at?: string | null;
  severity: 'LOW' | 'MEDIUM' | 'HIGH' | 'CRITICAL';
  priority?: string;
  assigned_to?: string;
  /**
   * Which tier of the command chain owns this incident — POLLING_UNIT, WARD,
   * LGA, HQ. Separate from `assigned_to`, which is a person's uuid: the tier
   * used to be crammed into that column and into `escalated_to_agency`, and
   * fitted neither.
   */
  assigned_tier?: string;
  /** When this incident reached its current tier — the escalation clock's start. */
  tier_assigned_at?: string;
  /** Null means NOBODY has taken this incident, and the tier timer is climbing. */
  acknowledged_at?: string | null;
  acknowledged_by?: string | null;
  escalated_to_agency?: string;
  escalation_log?: unknown[];
  /**
   * 'SMS' or 'MESH' when the report arrived over a degraded channel, meaning
   * the reporter had no data connection and `created_at` is the PHONE's clock.
   * Null for a report that came over the network. Written only by
   * src/lib/offline-alert-ingest.ts.
   */
  arrived_via?: string | null;
  assignedToUid?: string | null;
  latitude?: number;
  longitude?: number;
  lat?: number;
  lng?: number;
  reported_by?: string;
  geo_lga?: string;
  geo_ward?: string;
  geo_pu?: string;
  ai_summary?: string;
  citizen_feedback?: string;
  feedback_at?: string;
  post_sos_status?: string;
  media_urls?: string[];
  attachments?: string[];
  created_at?: string;
  updated_at?: string;
  resolved_by?: string;
  resolved_at?: string;
  timeline?: any[];
}
