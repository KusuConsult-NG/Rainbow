// Applying the AI's triage to an incident.
//
// The button said APPLY AI CLASSIFICATIONS and did four wrong things at once:
// applied no classification, marked the incident DISPATCHED with nobody
// assigned, could not tell whether its own write had failed, and was gated on a
// comparison that can never be true so it never went away.
//
// These tests hold the two decisions that make the new version safe: `type` is
// never overwritten, and status is never touched.
import { describe, expect, it } from 'vitest';

import {
  alreadyApplied,
  applyButtonLabel,
  currentSeverity,
  triageChanges,
} from './ai-triage-apply';

const HQ = { email: 'hq@operationrainbow.plateau.gov.ng', id: 'hq-1' };

const alert = (over: Record<string, unknown> = {}) => ({
  type: 'Kidnap - Immediate Abduction',
  severity: 'MEDIUM',
  ...over,
});

const triage = (over: Record<string, unknown> = {}) => ({
  recommended_type: 'CRIME',
  recommended_priority: 'CRITICAL',
  justification: 'Active weapons reported.',
  ...over,
});

describe('reading the current severity', () => {
  it('prefers the column over the console’s derived field', () => {
    expect(currentSeverity({ severity: 'HIGH', priority: 'LOW' })).toBe('HIGH');
  });

  it('falls back to the derived field, which is what a mapped row carries', () => {
    expect(currentSeverity({ priority: 'HIGH' })).toBe('HIGH');
  });

  it('is null for a grading this system does not use', () => {
    // 'UNKNOWN' is what the console substitutes for an ungraded alert. Treating
    // it as a severity would make "raise from UNKNOWN" look like a real change
    // in the wrong direction.
    expect(currentSeverity({ severity: 'UNKNOWN' })).toBeNull();
    expect(currentSeverity({})).toBeNull();
    expect(currentSeverity({ severity: '' })).toBeNull();
  });

  it('is case- and space-insensitive', () => {
    expect(currentSeverity({ severity: '  critical ' })).toBe('CRITICAL');
  });
});

describe('whether it has already been applied', () => {
  it('compares severity to severity', () => {
    expect(alreadyApplied(alert({ severity: 'CRITICAL' }), triage())).toBe(true);
    expect(alreadyApplied(alert({ severity: 'MEDIUM' }), triage())).toBe(false);
  });

  it('does NOT compare the reported type to a category', () => {
    // The original gate was `alert.type === triage.recommended_type`, comparing
    // 'Kidnap - Immediate Abduction' to 'CRIME'. Never equal, so the button was
    // shown for every incident ever graded — including right after being pressed.
    const applied = alert({ severity: 'CRITICAL', type: 'Kidnap - Immediate Abduction' });
    expect(applied.type).not.toBe(triage().recommended_type);
    expect(alreadyApplied(applied, triage())).toBe(true);
  });

  it('treats an unusable recommendation as nothing to apply', () => {
    // No control should be offered when the AI recommended nothing gradeable.
    for (const p of [null, undefined, '', 'SEVERE', 'urgent']) {
      expect(alreadyApplied(alert(), triage({ recommended_priority: p })), String(p)).toBe(true);
    }
  });
});

describe('what applying actually writes', () => {
  it('writes the severity and NOTHING else', () => {
    const { patch } = triageChanges(alert(), triage(), HQ);
    expect(patch).toEqual({ severity: 'CRITICAL' });
  });

  it('never touches status', () => {
    // The original set status to DISPATCHED with no assignee. A dispatcher
    // scanning for incidents that still need a unit skips anything marked
    // DISPATCHED, so the button quietly removed the incident from the list of
    // things needing attention while no unit had been sent.
    const { patch, note } = triageChanges(alert(), triage(), HQ);
    expect(patch).not.toHaveProperty('status');
    expect(patch).not.toHaveProperty('assigned_to');
    expect(note).toContain('Status not changed');
    expect(note).toContain('dispatch is a separate decision');
  });

  it('never overwrites the reported type', () => {
    // `recommended_type` is a bare category; `alerts.type` is
    // '<category> - <subtype>' and the generated `category` column derives from
    // it. Writing 'CRIME' would destroy the subtype the reporter chose AND break
    // the console's own category filter for that row.
    const { patch, note } = triageChanges(alert(), triage(), HQ);
    expect(patch).not.toHaveProperty('type');
    expect(patch).not.toHaveProperty('category');
    // It is recorded rather than imposed.
    expect(note).toContain('CRIME');
    expect(note).toContain('left as recorded');
  });

  it('records who applied it', () => {
    expect(triageChanges(alert(), triage(), HQ).note).toContain(HQ.email);
    expect(triageChanges(alert(), triage(), { id: 'u-9' }).note).toContain('u-9');
    expect(triageChanges(alert(), triage(), {}).note).toContain('an HQ operator');
  });

  it('records what it changed from and to', () => {
    const { note } = triageChanges(alert({ severity: 'LOW' }), triage(), HQ);
    expect(note).toContain('LOW → CRITICAL');
  });

  it('says "not set" rather than inventing a previous grading', () => {
    const { note, direction } = triageChanges(alert({ severity: null }), triage(), HQ);
    expect(note).toContain('not set → CRITICAL');
    expect(direction).toBe('set');
  });

  it('does nothing when it already matches', () => {
    const c = triageChanges(alert({ severity: 'CRITICAL' }), triage(), HQ);
    expect(c.patch).toEqual({});
    expect(c.direction).toBe('none');
    expect(c.note).toBe('');
  });

  it('does nothing when the recommendation is unusable', () => {
    const c = triageChanges(alert(), triage({ recommended_priority: 'VERY BAD' }), HQ);
    expect(c.patch).toEqual({});
    expect(c.direction).toBe('none');
  });
});

describe('the direction', () => {
  it('distinguishes raising from lowering', () => {
    // Different acts. Lowering CRITICAL to MEDIUM on an AI's word is the one that
    // deserves a second look, and an operator should be told which they are about
    // to do rather than reading two codes and working it out.
    expect(triageChanges(alert({ severity: 'LOW' }), triage(), HQ).direction).toBe('raised');
    expect(
      triageChanges(alert({ severity: 'CRITICAL' }), triage({ recommended_priority: 'MEDIUM' }), HQ)
        .direction,
    ).toBe('lowered');
  });

  it('is reflected on the control, so the operator reads it before pressing', () => {
    expect(applyButtonLabel(triageChanges(alert({ severity: 'LOW' }), triage(), HQ)))
      .toContain('RAISE');
    expect(
      applyButtonLabel(
        triageChanges(alert({ severity: 'CRITICAL' }), triage({ recommended_priority: 'LOW' }), HQ),
      ),
    ).toContain('LOWER');
    expect(applyButtonLabel(triageChanges(alert({ severity: null }), triage(), HQ)))
      .toContain('SET');
  });
});
