/**
 * How well an incident is corroborated: how many INDEPENDENT sources stand
 * behind it, over how many channels.
 *
 * Phase 1 of the intelligence layer (the "Rainbow Intelligence Layer" draft).
 * Before this, every report counted the same: ten presses of SOS on one phone
 * read as ten witnesses, and a hoax looked exactly like a massacre until
 * somebody drove out to see.
 *
 * ## The rules
 *
 * - A SOURCE is a person, not a report. Two reports from the same account, or
 *   from the same keypad number, are one source.
 * - A CHANNEL is how a report reached us: the app, AI Emergency Guardian, SMS,
 *   Bluetooth mesh, or USSD. Two channels are harder to fake than one.
 * - A USSD report nobody has stood behind yet (`awaitingConfirmation`, which
 *   mirrors the database's `awaiting_human_confirmation()`) is counted and
 *   SHOWN, but does not raise the level: anyone can dial a keypad menu from a
 *   handful of SIMs, and a burst of them is exactly what a decoy looks like.
 * - The level is a reading aid, not a verdict. A single source is
 *   UNCONFIRMED, never hidden and never downgraded in severity: one real
 *   person in danger is one source.
 *
 * Only Rainbow's own channels in phase 1. Phase 2 adds open sensors (a NASA
 * FIRMS fire detection near the incident counts as a source of its own).
 */

import type { Alert } from '@/app/dashboard/types';
import { isGuardianAlert } from './alert-display';
import { arrivedByKeypad, awaitingConfirmation, type ProvenanceAlert } from './ussd-provenance';

export type SourceChannel = 'APP' | 'GUARDIAN' | 'SMS' | 'MESH' | 'USSD';

export type CorroborationLevel = 'UNCONFIRMED' | 'CORROBORATED' | 'STRONG';

export interface Corroboration {
  level: CorroborationLevel;
  /** Independent sources that count towards the level. */
  sources: number;
  /** Keypad sources still awaiting an officer's confirmation: shown, not counted. */
  unconfirmedSources: number;
  /** Every report behind the incident, duplicates included. */
  reports: number;
  /** The channels the counted sources used, in a fixed order. */
  channels: SourceChannel[];
}

/** Two independent sources corroborate. */
export const CORROBORATED_AT = 2;
/** Three independent sources over at least two channels is strong. */
export const STRONG_SOURCES = 3;
export const STRONG_CHANNELS = 2;

const CHANNEL_ORDER: SourceChannel[] = ['APP', 'GUARDIAN', 'SMS', 'MESH', 'USSD'];

type Row = Pick<Alert, 'id' | 'reported_by' | 'description' | 'arrived_via'> & ProvenanceAlert;

/** The channel a report arrived over. */
export function channelOf(alert: Row): SourceChannel {
  const via = (alert.arrived_via ?? '').toUpperCase();
  if (via === 'USSD') return 'USSD';
  if (via === 'SMS') return 'SMS';
  if (via === 'MESH') return 'MESH';
  if (isGuardianAlert(alert)) return 'GUARDIAN';
  return 'APP';
}

/**
 * Who stands behind a report. A keypad report is its caller's number, since
 * USSD has no account; anything else is the reporting account. A report with
 * neither cannot be shown to share a source with any other, so it is its own.
 */
export function sourceOf(alert: Row): string {
  if (arrivedByKeypad(alert)) {
    const number = (alert.reporter_msisdn ?? '').replace(/\D/g, '').slice(-10);
    return number ? `msisdn:${number}` : `report:${alert.id}`;
  }
  return alert.reported_by ? `user:${alert.reported_by}` : `report:${alert.id}`;
}

/** The corroboration of the incident these reports describe. */
export function corroborate(reports: Row[]): Corroboration {
  const counted = new Map<string, Set<SourceChannel>>();
  const waiting = new Set<string>();

  for (const r of reports) {
    const source = sourceOf(r);
    if (awaitingConfirmation(r)) {
      waiting.add(source);
      continue;
    }
    const seen = counted.get(source) ?? new Set<SourceChannel>();
    seen.add(channelOf(r));
    counted.set(source, seen);
  }
  // A number that filed a confirmed report is already counted; its other,
  // unconfirmed reports add nothing.
  for (const s of counted.keys()) waiting.delete(s);

  const used = new Set<SourceChannel>();
  counted.forEach((cs) => cs.forEach((c) => used.add(c)));
  const channels = CHANNEL_ORDER.filter((c) => used.has(c));
  const sources = counted.size;

  let level: CorroborationLevel = 'UNCONFIRMED';
  if (sources >= STRONG_SOURCES && channels.length >= STRONG_CHANNELS) level = 'STRONG';
  else if (sources >= CORROBORATED_AT) level = 'CORROBORATED';

  return {
    level,
    sources,
    unconfirmedSources: waiting.size,
    reports: reports.length,
    channels,
  };
}

/** One line for the incident card and the map popup. */
export function corroborationLine(c: Corroboration): string {
  const parts = [
    `${c.sources} independent source${c.sources === 1 ? '' : 's'}`,
  ];
  if (c.channels.length > 0) {
    parts.push(`${c.channels.length} channel${c.channels.length === 1 ? '' : 's'} (${c.channels.join(', ')})`);
  }
  if (c.unconfirmedSources > 0) {
    parts.push(`+${c.unconfirmedSources} unconfirmed keypad`);
  }
  if (c.reports > c.sources + c.unconfirmedSources) {
    parts.push(`${c.reports} reports`);
  }
  return parts.join(' · ');
}

/**
 * Each card's corroboration, from the raw reports clusterAlerts folded into it
 * (`member_ids`). A card that is not a cluster is its own one report.
 *
 * Done after clustering, not inside it, so the clustering rule and the
 * corroboration rule stay separate and separately tested.
 */
export function withCorroboration(cards: Alert[], raw: Alert[]): Alert[] {
  const byId = new Map(raw.map((r) => [r.id, r]));
  return cards.map((card) => {
    const members = (card.member_ids ?? [card.id])
      .map((id) => byId.get(id))
      .filter((r): r is Alert => r !== undefined);
    return { ...card, corroboration: corroborate(members.length ? members : [card]) };
  });
}
