import { describe, expect, it } from 'vitest';

import {
  describeSimEvent,
  isRenderableChange,
  severityOf,
} from './SimChannelEvents';

describe('what an operator is told about a handset', () => {
  it('says what a removal costs, not just that it happened', () => {
    // "SIM REMOVED" alone is a fact about a phone. What an operator needs is
    // what it means for reaching this person.
    const text = describeSimEvent({ change: 'REMOVED', operator_name: null });
    expect(text.toLowerCase()).toContain('sms');
    expect(text.toLowerCase()).toContain('cannot reach');
  });

  it('names the new network on a replacement', () => {
    expect(
      describeSimEvent({ change: 'REPLACED', operator_name: 'Airtel' }),
    ).toContain('Airtel');
  });

  it('does not invent a network it was not given', () => {
    const text = describeSimEvent({ change: 'REPLACED', operator_name: null });
    expect(text).toContain('a different network');
    expect(text).not.toContain('null');
    expect(text).not.toContain('undefined');
  });
});

describe('what the board will render', () => {
  it('accepts only the three changes the schema allows', () => {
    expect(isRenderableChange('REMOVED')).toBe(true);
    expect(isRenderableChange('INSERTED')).toBe(true);
    expect(isRenderableChange('REPLACED')).toBe(true);
  });

  it('refuses anything else', () => {
    // The row is written by a handset. A compromised one must not be able to
    // put prose on an operator's screen, so the words are composed here from
    // the code and an unrecognised code is dropped rather than rendered.
    expect(isRenderableChange('<script>alert(1)</script>')).toBe(false);
    expect(isRenderableChange('URGENT: CALL THIS NUMBER')).toBe(false);
    expect(isRenderableChange('')).toBe(false);
    expect(isRenderableChange('removed')).toBe(false);
  });
});

describe('severity', () => {
  it('treats a removal and a replacement as the channel being down', () => {
    expect(severityOf('REMOVED')).toBe('alert');
    expect(severityOf('REPLACED')).toBe('alert');
  });

  it('treats a SIM coming back as good news', () => {
    expect(severityOf('INSERTED')).toBe('note');
  });
});
