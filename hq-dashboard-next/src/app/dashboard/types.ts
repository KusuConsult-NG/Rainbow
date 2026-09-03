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
  description?: string;
  status: 'PENDING' | 'DISPATCHED' | 'ACKNOWLEDGED' | 'ON_ROUTE' | 'ON_SITE' | 'RESOLVED' | 'DURESS' | 'CANCELLED';
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
  assignedToUid?: string | null;
  latitude?: number;
  longitude?: number;
  lat?: number;
  lng?: number;
  reported_by?: string;
  reportedBy?: string;
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
  reportedAt?: any;
  resolved_by?: string;
  resolved_at?: string;
  timeline?: any[];
}
