// Translating an aggregator's callback into what the menu needs.
//
// Every one of these assertions is about a failure that only shows up in
// production. A misread field name, or an accumulated input string fed to a
// reducer expecting one keypress, produces a menu that restarts on every screen
// — and a unit test that sends one key at a time never notices.
import { describe, expect, it } from 'vitest';

import { canonicalMsisdn, latestKeypress, normalise, renderReply } from './ussd-gateway';

describe('the latest keypress', () => {
  it('takes the last segment when the aggregator accumulates input', () => {
    // Africa's Talking sends the whole '*'-joined path. Handing '1*2*4' to the
    // reducer makes every screen after the first behave as a mis-key.
    expect(latestKeypress('1*2*4')).toBe('4');
    expect(latestKeypress('1*1')).toBe('1');
  });

  it('passes a single keypress through untouched', () => {
    // Most carrier-direct integrations send only the new key. Both conventions
    // work without the adapter being told which is in use, because a keypress
    // never contains '*' — the menu is digits only.
    expect(latestKeypress('4')).toBe('4');
    expect(latestKeypress('99')).toBe('99');
  });

  it('treats an opening session and a trailing star as no keypress', () => {
    expect(latestKeypress('')).toBe('');
    expect(latestKeypress(undefined)).toBe('');
    expect(latestKeypress('   ')).toBe('');
    // Some gateways send this when send is pressed on an empty screen.
    expect(latestKeypress('1*')).toBe('');
  });

  it('trims whitespace the gateway added', () => {
    expect(latestKeypress(' 1 * 2 ')).toBe('2');
  });
});

describe('the MSISDN', () => {
  it('brings every Nigerian form to one shape', () => {
    // The same SIM must not appear three ways on a dispatcher's board.
    for (const raw of ['08030001111', '2348030001111', '+2348030001111', '+234 803 000 1111']) {
      expect(canonicalMsisdn(raw), raw).toBe('+2348030001111');
    }
  });

  it('handles a ten-digit number with no leading zero', () => {
    expect(canonicalMsisdn('8030001111')).toBe('+2348030001111');
  });

  it('leaves something too short alone rather than inventing a country code', () => {
    // A shortcode or a malformed value must not be dressed up as a real number:
    // it would then be recorded as the reporter and rung back.
    expect(canonicalMsisdn('1234')).toBe('1234');
    expect(canonicalMsisdn('')).toBe('');
  });
});

describe('normalising a callback', () => {
  const AT = {
    sessionId: 'ATUid_abc123',
    phoneNumber: '+2348030001111',
    serviceCode: '*347*100#',
    text: '1*2',
  };

  it('reads the Africa’s Talking shape', () => {
    const r = normalise(AT);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.request).toMatchObject({
      sessionId: 'ATUid_abc123',
      msisdn: '+2348030001111',
      input: '2',
      serviceCode: '*347*100#',
    });
  });

  it('reads snake_case and upper-case variants', () => {
    const r = normalise({ session_id: 'S1', MSISDN: '08030001111', userInput: '3' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.request).toMatchObject({ sessionId: 'S1', msisdn: '+2348030001111', input: '3' });
  });

  it('reads `from` and `ussdString`, which some carrier integrations use', () => {
    const r = normalise({ sessionID: 'S2', from: '2348030002222', ussdString: '1*1*1' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.request.input).toBe('1');
    expect(r.request.msisdn).toBe('+2348030002222');
  });

  it('accepts a session that has just opened, with no input at all', () => {
    // The common case, and it must NOT be an error: this is somebody dialling.
    const r = normalise({ sessionId: 'S3', phoneNumber: '08030003333' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.request.input).toBe('');
  });

  it('refuses a callback with no session id', () => {
    // Without it there is no dialogue to continue and no way to deduplicate a
    // retry, which is the one thing that must not be guessed.
    const r = normalise({ phoneNumber: '08030001111', text: '1' });
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.reason).toContain('session id');
  });

  it('refuses a callback with no MSISDN', () => {
    // No reporter, no callback channel, no way to read the report back.
    const r = normalise({ sessionId: 'S4', text: '1' });
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.reason).toContain('msisdn');
  });

  it('refuses rather than reading an unrecognised shape as an empty keypress', () => {
    // The defect this whole module exists to prevent: an adapter that silently
    // reads `undefined` restarts the menu on every screen, and nobody can tell
    // why from the outside.
    const r = normalise({ dialogueRef: 'X', callerId: '08030001111', keys: '2' });
    expect(r.ok).toBe(false);
  });

  it('ignores a numeric zero and an empty string when picking a field', () => {
    // `0` as a session id is not a session id, and '' is not an MSISDN.
    expect(normalise({ sessionId: '', phoneNumber: '08030001111' }).ok).toBe(false);
    expect(normalise({ sessionId: 'S5', phoneNumber: '   ' }).ok).toBe(false);
  });

  it('does not let a number-typed session id break the mapping', () => {
    const r = normalise({ sessionId: 12345, phoneNumber: '08030001111', text: '1' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.request.sessionId).toBe('12345');
  });
});

describe('rendering the reply', () => {
  it('uses CON to keep the session open and END to close it', () => {
    expect(renderReply('Pick one', false, 'AT_TEXT').body).toBe('CON Pick one');
    expect(renderReply('Sent.', true, 'AT_TEXT').body).toBe('END Sent.');
  });

  it('sends plain text, not JSON, in the text convention', () => {
    // A JSON content type on a gateway expecting text is answered with a blank
    // screen on the handset and no error anywhere.
    expect(renderReply('x', false, 'AT_TEXT').contentType).toContain('text/plain');
  });

  it('carries the session state and the message in the JSON convention', () => {
    const { body, contentType } = renderReply('Sent.', true, 'JSON');
    expect(contentType).toContain('application/json');
    expect(JSON.parse(body)).toEqual({ sessionState: 'END', message: 'Sent.' });
    expect(JSON.parse(renderReply('Pick', false, 'JSON').body))
      .toMatchObject({ sessionState: 'CONTINUE' });
  });

  it('keeps a multi-line screen intact', () => {
    // USSD menus are newline-separated; a render that collapsed them would show
    // one run-on line on the handset.
    const screen = 'Line one\nLine two';
    expect(renderReply(screen, false, 'AT_TEXT').body).toBe('CON Line one\nLine two');
    expect(JSON.parse(renderReply(screen, false, 'JSON').body).message).toBe(screen);
  });
});
