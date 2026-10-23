#!/usr/bin/env python3
"""A live stream must not be announced before it connects.

    python3 scripts/check_a_live_stream_is_not_claimed_early.py

## What went wrong

`live_stream_service.dart` lets somebody in an emergency show HQ what is
happening to them. `startStream()` returned `true` as soon as it had broadcast
the WebRTC offer — no answer, no ICE candidate, no connection — and nothing
anywhere registered `onConnectionState`. The screen did this with it:

    final success = await LiveStreamService().startStream(alertId);
    setState(() => _isLiveStreaming = success);
    ... success ? '🔴 ${_t('eme_broadcast_live')}' : _t('eme_stream_failed')

So a person in danger saw a red BROADCASTING LIVE TO HQ and the camera light
come on, having established nothing.

That is word for word the experience the note at the top of that file describes
for the `type`/`broadcast` signalling collision: "Somebody in an emergency
believed they were showing HQ what was happening to them, with the camera light
on to confirm it, and nobody was receiving anything." The collision was found
and fixed. **The thing that made it invisible was not** — so the next failure in
the chain reproduced it exactly.

And there is a next failure. Both sides' ICE configuration was three of
Google's public STUN servers, written in as literals, with no TURN relay. STUN
discovers an address; it cannot relay. A handset is behind carrier-grade NAT,
which is commonly symmetric, and symmetric NAT on either side defeats UDP hole
punching — so without a relay the media has no route. The feature worked when
the network happened to allow it, which for a phone on mobile data is the
exception, and the screen said it was live regardless.

## What this checks

1. The emergency screen reads the connection STATUS, not `startStream`'s return
   value, for anything it puts in front of a person.
2. The service registers `onConnectionState` and reports `live` only on
   `Connected`.
3. Neither side hardcodes an ICE server list. The handset reads
   `lib/core/config/live_stream.dart`; the console reads `/api/rtc/config`,
   because a TURN credential cannot be `NEXT_PUBLIC_` — that is inlined into
   the browser bundle at build time, which is how this project once shipped its
   Gemini key.
4. The console viewer distinguishes a failed connection from standby. It did
   not: `FAILED` fell through to the same `STANDBY` label as "nobody has
   pressed the button".
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SERVICE = REPO / 'lib/services/live_stream_service.dart'
SCREEN = REPO / 'lib/features/emergency/emergency_active_screen.dart'
CONFIG = REPO / 'lib/core/config/live_stream.dart'
VIEWER = REPO / 'hq-dashboard-next/src/components/LiveFeedViewer.tsx'
RTC_ROUTE = REPO / 'hq-dashboard-next/src/app/api/rtc/config/route.ts'

# `stun:` or `turn:` inside a source file. The config module and the route are
# where they belong; anywhere else is a list that cannot be changed by whoever
# deploys it.
ICE_LITERAL = re.compile(r"['\"](?:stun|turns?):[^'\"]+['\"]")

faults: list[str] = []
proved: list[str] = []


def live(path: Path) -> str:
    """Comments blanked, newlines kept so line numbers stay true."""
    src = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)),
                 path.read_text(encoding='utf-8'), flags=re.S)
    opener = ('//', '///')
    return '\n'.join(
        '' if line.lstrip().startswith(opener) else line
        for line in src.split('\n'))


for path in (SERVICE, SCREEN, CONFIG, VIEWER, RTC_ROUTE):
    if not path.is_file():
        faults.append(
            f'{path.relative_to(REPO)} is missing. Without it the stream goes '
            f'back to announcing itself before it connects.')
if faults:
    print('FAIL: a live stream may be claimed before it connects.\n')
    for f in faults:
        print(f'  - {f}\n')
    sys.exit(1)

service, screen, viewer = live(SERVICE), live(SCREEN), live(VIEWER)

# ── 1. the screen reads the status, not the return value ────────────────────
if 'LiveStreamStatus' not in screen or 'statusStream' not in screen:
    faults.append(
        'emergency_active_screen.dart does not listen to '
        '`LiveStreamService().statusStream`. Whatever it shows the person then '
        'comes from `startStream()`, which returns as soon as the offer is '
        'broadcast — the red BROADCASTING LIVE TO HQ over a connection that '
        'does not exist.')
else:
    # The old shape, specifically: the live flag taken straight from the call.
    if re.search(r'_isLiveStreaming\s*=\s*await\s+LiveStreamService\(\)\.startStream',
                 screen):
        faults.append(
            'emergency_active_screen.dart still assigns its live flag directly '
            'from `startStream()`. That call means "the camera is on and an '
            'offer has gone out", not "HQ is receiving".')
    # And the red label must be behind the connected state.
    if not re.search(r'_streamStatus\s*==\s*LiveStreamStatus\.live', screen):
        faults.append(
            'nothing in emergency_active_screen.dart gates anything on '
            '`LiveStreamStatus.live`, so the screen cannot tell a connected '
            'stream from one that is still negotiating.')
    if not faults:
        proved.append('the screen shows what the connection reports, not what '
                      'the call returned')

# ── 2. the service watches the connection ──────────────────────────────────
if 'onConnectionState' not in service:
    faults.append(
        'live_stream_service.dart does not register `onConnectionState`. That '
        'is the only thing that knows whether HQ is receiving, and it went '
        'unread while the screen answered the question anyway.')
elif not re.search(r'RTCPeerConnectionStateConnected:\s*\n?\s*_setStatus\('
                   r'LiveStreamStatus\.live\)', service):
    faults.append(
        '`live` is not reported from `RTCPeerConnectionStateConnected`. Any '
        'other trigger for it is a guess, which is the defect.')
else:
    proved.append('`live` is reported only when the peer connection says '
                  'connected')

# ── 3. no hardcoded ICE list outside the two places that own it ────────────
for path, where in ((SERVICE, service), (SCREEN, screen), (VIEWER, viewer)):
    for m in ICE_LITERAL.finditer(where):
        # The console viewer keeps a STUN-only fallback for when the route
        # cannot be read, which is deliberate and sits beside the fetch.
        window = where[max(0, m.start() - 600):m.start()]
        if path == VIEWER and '/api/rtc/config' in where and 'rtcConfig' in window:
            continue
        line = where.count('\n', 0, m.start()) + 1
        faults.append(
            f'{path.relative_to(REPO)}:{line} writes an ICE server in as a '
            f'literal ({m.group(0)}). Whoever deploys this cannot add a TURN '
            f'relay, and without one the media has no route through carrier '
            f'NAT — the connection the screen was announcing.')
if not any('ICE server in as a literal' in f for f in faults):
    proved.append('ICE servers come from configuration on both sides')

# A TURN credential must never be inlined into the browser bundle.
for path in sorted((REPO / 'hq-dashboard-next/src').rglob('*.ts')):
    text = path.read_text(encoding='utf-8', errors='replace')
    if re.search(r'NEXT_PUBLIC_TURN', text):
        faults.append(
            f'{path.relative_to(REPO)} reads a NEXT_PUBLIC_TURN_* variable. '
            f'NEXT_PUBLIC_* is inlined into the client bundle at build time, '
            f'so the relay credential would be served to every visitor and '
            f'frozen at whatever the build machine had. This project already '
            f'shipped its Gemini key that way; see src/lib/env.ts.')

# ── 4. the console tells a failed connection from standby ──────────────────
#
# Three specific constructs, not the string 'FAILED' anywhere in the file. The
# first version of this looked for the string, and a mutation that deleted the
# state, the label and the assignment still passed — because 'FAILED' remained
# in the three ternaries that pick a BADGE COLOUR. A colour is not a state.
if not re.search(r"useState<[^>]*'FAILED'[^>]*>", viewer):
    faults.append(
        "LiveFeedViewer.tsx's status type has no 'FAILED', so a stream that "
        'tried and could not connect cannot be told from one nobody has '
        'started — both read STANDBY.')
elif "setStatus('FAILED')" not in viewer:
    faults.append(
        "LiveFeedViewer.tsx never sets 'FAILED'. The state exists and nothing "
        'reaches it, so the viewer sits on CONNECTING for ever when ICE gives '
        'up.')
# The branch has to produce a LABEL, not a colour. `status === 'FAILED' ?
# '[^']+'` matched `'rgba(239,68,68,0.12)'` in the badge background, so deleting
# the label and keeping the colours passed — twice in a row, in the check
# written to stop exactly that.
elif not re.search(r"status === 'FAILED' \? '(?!rgba\(|#|var\(|1px )[^']+'",
                   viewer):
    faults.append(
        "LiveFeedViewer.tsx sets 'FAILED' and shows no label for it, so the "
        'badge falls through to STANDBY and HQ reads a failed connection as '
        'nobody having started one.')
elif 'onconnectionstatechange' not in viewer:
    faults.append(
        'LiveFeedViewer.tsx never reads `onconnectionstatechange`, so it sits '
        'on CONNECTING for ever when ICE gives up and HQ cannot tell "still '
        'negotiating" from "this will never connect".')
else:
    proved.append('the console distinguishes a failed connection from standby')

if faults:
    print('FAIL: a live stream may be claimed before it connects.\n')
    for f in faults:
        print(f'  - {f}\n')
    print('See E2E_AUDIT_REPORT.md T-96.')
    sys.exit(1)

print('OK: a live stream is announced only once it is connected.')
for item in proved:
    print(f'  * {item}')
