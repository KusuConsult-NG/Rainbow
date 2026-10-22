#!/usr/bin/env python3
"""A tracked SOS must write an id the database will take, and follow it at sync.

    python3 scripts/check_a_tracked_sos_reaches_the_map.py

## What went wrong

> when there is an SOS, what is sent as an alert, is the phone number,
> coordinates and the responder should be able to engage and track the alert
> device or monitor the movement of the alert

`alerts.id` is a UUID. `telemetry.alert_id` and `incident_tracks.alert_id` are
UUID columns with a foreign key to it. An SOS raised while the handset has no
data path is queued into local SQLite and tracked against `newOfflineLocalId()`
— `OFFLINE_<millis>_<12 hex>` — which is not a UUID.

`background_tracking_service.dart` put that straight into both payloads.
PostgreSQL rejects it at the TYPE, before the foreign key is consulted:
`22P02 invalid input syntax for type uuid`.

For `incident_tracks` that lost the route. For `telemetry` it lost more: the id
sits in the same payload as the position, so the WHOLE upsert was refused and
the dispatcher watching an offline SOS saw no dot at all — for the length of
the emergency, with `[TELEMETRY_FAIL]` in a debug log as the only trace.

And it never recovered. `_flushOfflineQueueOnce` computes a local-id-to-UUID
mapping when the queue drains, returned it, and nothing consumed it. The track
stayed bound to an id no table would accept even after the alert had a real
row.

This is the offline case — which is the case this app is for. A citizen with a
data connection has other ways to call for help.

## What this checks

1. Every `alert_id` written into `telemetry` or `incident_tracks` from the
   tracking service is guarded by `isServerAlertId`.
2. `isServerAlertId` actually matches a UUID rather than, say, rejecting a
   prefix — a `!startsWith('OFFLINE_')` check would pass any other junk.
3. The queue flush calls `rebindAlertId`, so a track started offline follows
   the alert to its real row.
4. `rebindAlertId` only moves a track that is bound to the local id it was
   given, so flushing old reports cannot hijack a live track.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TRACKING = REPO / 'lib/services/background_tracking_service.dart'
ALERTS = REPO / 'lib/services/alert_service.dart'

faults: list[str] = []
proved: list[str] = []


def live(path: Path) -> str:
    if not path.exists():
        faults.append(f'{path.relative_to(REPO)} is missing')
        return ''
    src = re.sub(r'/\*.*?\*/', lambda m: re.sub(r'[^\n]', ' ', m.group(0)),
                 path.read_text(), flags=re.S)
    return '\n'.join(
        '' if line.lstrip().startswith(('//', '///')) else line
        for line in src.split('\n'))


tracking, alerts = live(TRACKING), live(ALERTS)
if faults:
    print('FAIL:')
    for f in faults:
        print(f'  - {f}')
    sys.exit(1)

# ── 1. every alert_id write is guarded ──────────────────────────────────────
writes = list(re.finditer(r"'alert_id'\s*:\s*([A-Za-z_][\w.]*)", tracking))
if not writes:
    faults.append(
        'the tracking service writes no `alert_id` at all. Without it a point '
        'belongs to no incident and the route cannot be drawn.')
for match in writes:
    # The guard must name THE SAME variable, within a few lines above. Tying
    # it to the identifier is what makes this precise: a nearby
    # `isServerAlertId(somethingElse)` does not protect this write, and a bare
    # proximity check would accept one. The first version of this check looked
    # at three lines and reported the `incident_tracks` insert, whose guard is
    # four lines up — a false positive found by running it.
    written = match.group(1)
    line_no = tracking[:match.start()].count('\n')
    window = '\n'.join(tracking.split('\n')[max(0, line_no - 6):line_no + 1])
    if f'isServerAlertId({written})' not in window:
        faults.append(
            f'{TRACKING.relative_to(REPO)}:{line_no + 1} writes `alert_id` '
            f'without checking `isServerAlertId` first. An offline SOS carries '
            f'OFFLINE_<millis>_<hex>, which a UUID column refuses at the type '
            f'— and for `telemetry` that refusal takes the position with it.')
if writes and not faults:
    proved.append(f'all {len(writes)} alert_id writes are guarded by '
                  f'isServerAlertId')

# ── 2. the guard is a real UUID test ────────────────────────────────────────
guard = re.search(r'static bool isServerAlertId\([^)]*\)\s*\{(.*?)\n  \}',
                  tracking, re.S)
if guard is None:
    faults.append('there is no `isServerAlertId` to guard with')
else:
    body = guard.group(1)
    if '[0-9a-fA-F]{12}' not in body or '{8}' not in body:
        faults.append(
            '`isServerAlertId` does not test the shape of a UUID. A check for '
            'an OFFLINE_ prefix passes every other kind of junk, and the point '
            'is what the COLUMN will take, not what this app happens to mint.')
    else:
        proved.append('isServerAlertId matches a UUID, not a prefix')

# ── 3. the queue flush rebinds ──────────────────────────────────────────────
if 'rebindAlertId' not in alerts:
    faults.append(
        f'{ALERTS.relative_to(REPO)} never calls `rebindAlertId`. The flush '
        f'computes the local-id-to-UUID mapping and the tracker is not told, '
        f'so a track started offline stays bound to an id no table accepts '
        f'even after the alert has a real row.')
else:
    proved.append('the queue flush hands the real id to the tracker')

# ── 4. rebinding cannot hijack another track ────────────────────────────────
rebind = re.search(r'Future<void> rebindAlertId\([^)]*\)\s*async\s*\{(.*?)\n  \}',
                   tracking, re.S)
if rebind is None:
    faults.append('there is no `rebindAlertId`')
else:
    body = rebind.group(1)
    if "activeTrackingAlertId') != localId" not in body.replace('"', "'"):
        faults.append(
            '`rebindAlertId` does not check that the track it is moving is the '
            'one it was given. A flush that syncs several old reports would '
            'then repoint a LIVE track at whichever finished last.')
    elif 'isServerAlertId' not in body:
        faults.append(
            '`rebindAlertId` does not check the id it is moving TO. Rebinding '
            'one unusable id onto another changes nothing.')
    else:
        proved.append('rebinding moves only the named track, to a real id')

if faults:
    print('FAIL: a tracked SOS may not reach the map.\n')
    for f in faults:
        print(f'  - {f}\n')
    sys.exit(1)

print('OK: a tracked SOS writes an id the database takes, and follows it.')
for item in proved:
    print(f'  * {item}')
